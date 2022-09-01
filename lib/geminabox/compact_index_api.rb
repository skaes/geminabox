module Geminabox
  class CompactIndexApi

    include Gem::UserInteraction

    attr_reader :cache

    def initialize
      @cache = RemoteCache.new
      @api = RubygemsCompactIndexApi.new
    end

    def names
      local_gem_list = Set.new(all_gems.list)
      return format_gem_names(local_gem_list) unless Geminabox.rubygems_proxy

      remote_name_data = remote_names
      return format_gem_names(local_gem_list) unless remote_name_data

      remote_gem_list = remote_name_data.split("\n")[1..-1]
      format_gem_names(local_gem_list.merge(remote_gem_list))
    end

    def local_names
      format_gem_names(Set.new(all_gems.list))
    end

    def remote_names
      fetch("names") do |etag|
        @api.fetch_names(etag)
      end
    end

    def combined_versions_file
      Geminabox.data+"versions.combined"
    end

    def combined_versions_file_fresh?
      File.exist?(combined_versions_file) && (Geminabox.external_index_update || (Time.now - File.mtime(combined_versions_file) < 60))
    end

    def remove_combined_versions_file
      FileUtils.rm_f(combined_versions_file)
    end

    def update_combined_versions_file
      Gem.time "Updated combined versions file" do
        say "Fetching remote versions file"
        local_versions = self.local_versions
        remote_versions = self.remote_versions

        dependencies_last_modified = [compact_indexer.versions_path, cache.path("versions")].map{|p| File.mtime(p)}.max
        combined_data_fresh = File.exist?(combined_versions_file) && File.mtime(combined_versions_file) > dependencies_last_modified

        if combined_data_fresh
          say "Combined versions file not modified"
          return File.binread(combined_versions_file)
        end

        combined_versions = GemVersionsMerge.merge(local_versions, remote_versions)

        f = Tempfile.new("geminabox-combined-versions", binmode: true)
        f.write(combined_versions)
        f.close
        FileUtils.chmod(Geminabox.gem_permissions, f.path)
        FileUtils.mv(f.path, combined_versions_file)

        combined_versions
      end
    end

    def versions
      return local_versions unless Geminabox.rubygems_proxy
      return File.binread(combined_versions_file) if combined_versions_file_fresh?

      begin
         Server.with_rlock { update_combined_versions_file }
      rescue ReentrantFlock::AlreadyLocked
        # Use the potentially outdated combined versions file if we can't get the lock.
        File.binread(combined_versions_file)
      end
    end

    def info(name)
      if Geminabox.rubygems_proxy
        local_gem_info(name) || remote_gem_info(name)
      else
        local_gem_info(name)
      end
    end

    def remote_versions
      fetch("versions") do |etag|
        @api.fetch_versions(etag)
      end
    end

    def local_versions
      compact_indexer.fetch_versions
    end

    def remote_gem_info(name)
      fetch("info/#{name}") do |etag|
        @api.fetch_info(name, etag)
      end
    end

    def local_gem_info(name)
      compact_indexer.fetch_info(name)
    end

    def all_gems
      Geminabox::GemVersionCollection.new(Specs.all_gems)
    end

    def compact_indexer
      @compact_indexer ||= CompactIndexer.new
    end

    def determine_proxy_status(verbose = nil)
      remote_version_info = VersionInfo.new
      remote_version_info.content = remote_versions

      local_gem_names = names_to_set(local_names).to_a
      status_and_conflicts = Parallel.map(local_gem_names, in_threads: 10) do |name|
        [name, *proxy_status(name, remote_version_info)]
      end

      report_proxy_status(status_and_conflicts) if verbose

      status_and_conflicts.map { |name, status, _| name if status == :proxied }.compact
    end

    def report_proxy_status(status_and_conflicts)
      status_and_conflicts.sort_by(&:first).each do |name, status, conflicts|
        extra = ": #{conflicts.join(', ')}" if conflicts
        say "#{name}: #{status}#{extra}"
      end
    end

    def remove_proxied_gems_from_local_index
      proxied = determine_proxy_status
      proxied_versions = all_gems.by_name.to_h.select do |name, _|
        proxied.include?(name)
      end

      gem_count = proxied_versions.values.map(&:size).inject(0, :+)
      if gem_count.zero?
        say "No gems to move to the proxy cache"
        say "Run geminabox reindex if you want to rebuild all indexes"
        return
      end

      say "Moving #{gem_count} proxied gem versions to proxy cache"
      proxied_versions.each_value do |versions|
        versions.each do |version|
          move_gem_to_proxy_cache("#{version.gemfile_name}.gem")
        end
      end

      say "Rebuilding all indexes"
      Indexer.new.reindex(:force_rebuild)
    end

    def move_gems_from_proxy_cache_to_local_index
      clean_remote_cache

      gems_to_move = Dir["#{cache.gems_dir}/*.gem"]
      gem_count = gems_to_move.size

      if gem_count.zero?
        say "No gems to move to the local index"
        say "Run geminabox reindex if you want to rebuild all indexes"
        return
      end

      say "Moving #{gem_count} proxied gem versions to local index"
      FileUtils.mv(gems_to_move, File.join(Geminabox.data, "gems"))

      say "Rebuilding all indexes"
      Indexer.new.reindex(:force_rebuild)
    end

    private

    def clean_remote_cache
      # Remove all gems from remote cache that also have local versions.
      # Moving those gems to a standalone server would be a security risk.
      gems = Dir["#{cache.gems_dir}/*.gem"]
      count = gems.size + 1
      n = Geminabox.workers

      title = "Cleaning remote gems cache of size #{count}"
      progressbar_options = Gem::DefaultUserInteraction.ui.outs.tty? && n > 1 && {
        title: title,
        total: count,
        format: '%t %b',
        progress_mark: '.'
      }
      say title unless progressbar_options

      local_gem_names = Set.new(all_gems.list)
      gems_to_remove = Parallel.map(gems, progress: progressbar_options, in_processes: n) do |path|
        local_gem_names.include?(Gem::Package.new(path.to_s).spec.name) ? path : nil
      end.compact

      gems_to_remove.each do |path|
        say "\nRemoving conflicting gems from remote cache: #{File.basename(path)}"
        FileUtils.rm(path)
      end
    end

    def move_gem_to_proxy_cache(gemfile)
      gemfile_path = File.join(Geminabox.data, "gems", gemfile)
      cache_path = cache.cache_path.join("gems", gemfile)
      FileUtils.mv(gemfile_path, cache_path)
    end

    def names_to_set(raw_names)
      Set.new(raw_names.split("\n")[1..-1])
    end

    def proxy_status(name, remote_version_info)
      local_info = DependencyInfo.new(name)
      local_info.content = local_gem_info(name)

      remote_info_digest = remote_version_info.digests[name]
      return [:local, nil] unless remote_info_digest

      remote_info = remote_info_for_gem(name, remote_info_digest)

      proxy_status_from_local_and_remote_info(local_info, remote_info)
    end

    def remote_info_for_gem(name, remote_info_digest)
      cached_remote_info_up_to_date = cache.md5("info/#{name}") == remote_info_digest
      remote_data = cached_remote_info_up_to_date ? cache.read("info/#{name}") : remote_gem_info(name)

      DependencyInfo.new(name).tap do |remote_info|
        remote_info.content = remote_data
      end
    end

    def proxy_status_from_local_and_remote_info(local_info, remote_info)
      if local_info.subsumed_by?(remote_info)
        [:proxied, nil]
      elsif local_info.disjoint?(remote_info)
        [:disjoint, local_info.version_names]
      else
        [:conflicts, local_info.conflicts(remote_info)]
      end
    end

    def format_gem_names(gem_list)
      ["---", gem_list.to_a.sort, ""].join("\n")
    end

    def fetch(path)
      etag = cache.md5(path)
      code, data = yield etag
      if code == 200
        cache.store(path, data)
      else # 304, 503, etc...
        cache.read(path)
      end
    end

  end
end

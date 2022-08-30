# frozen_string_literal: true

require 'tempfile'
require 'fileutils'
require 'rubygems/util'

module Geminabox
  module Proxy
    class Splicer < FileHandler

      attr_reader :cache

      def initialize(file_name)
        super
        @cache = RemoteCache.new
      end

      def self.make(file_name)
        splicer = new(file_name)
        splicer.create
        splicer
      end

      def create
        if content = new_content
          store_content(content)
        end
      end

      def new_content
        remote_content = self.remote_content
        return remote_content unless local_file_exists?

        new_remote_data = cache.md5(file_name) != Digest::MD5.hexdigest(remote_content)
        cache.store(file_name, remote_content) if new_remote_data

        dependencies_last_modified = [local_path, cache.path(file_name)].map{|p| File.mtime(p)}.max
        return nil if splice_file_exists? && File.mtime(splice_path) > dependencies_last_modified

        merge_content(local_content, remote_content)
      end

      def splice_path
        proxy_path
      end

      def splice_file_exists?
        file_exists? splice_path
      end

      def merge_content(local_data, remote_data)
        if gzip?
          merge_gzipped_content(local_data, remote_data)
        else
          merge_text_content(local_data, remote_data)
        end
      end

      def gzip?
        /\.gz$/ =~ file_name
      end

      private

      def merge_gzipped_content(local_data, remote_data)
        package(unpackage(local_data) | unpackage(remote_data))
      end

      def unpackage(content)
        Marshal.load(Gem::Util.gunzip(content))
      end

      def package(content)
        Gem::Util.gzip(Marshal.dump(content))
      end

      def merge_text_content(local_data, remote_data)
        local_data.to_s + remote_data.to_s
      end

      def store_content(content)
        f = Tempfile.create('geminabox')
        f.binmode
        begin
          f.write(content)
        ensure
          f.close rescue nil
        end
        FileUtils.mv(f.path, splice_path)
        File.chmod(Geminabox.gem_permissions, splice_path)
      end

    end
  end
end

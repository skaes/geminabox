require 'time'
require 'set'

module Geminabox
  module GemVersionsMerge
    def self.merge(local_gem_list, remote_gem_list)
      return local_gem_list unless remote_gem_list
      return remote_gem_list unless local_gem_list

      local_split = local_gem_list.split("\n")
      remote_split = remote_gem_list.split("\n")

      preamble = younger_created_at_header(local_split.shift(2), remote_split.shift(2))

      remove_local_gems(local_split, remote_split)

      "#{(preamble + remote_split + local_split).join("\n")}\n"
    end

    def self.younger_created_at_header(local_split, remote_split)
      t1 = Time.parse(local_split[0].split[1])
      t2 = Time.parse(remote_split[0].split[1])
      (t1 > t2 ? local_split : remote_split)[0..1]
    end

    def self.gem_names(split)
      split.each_with_object(Set.new) do |line, gems|
        line =~ /\A([^\s]+)\s.*\z/ && gems << $1
      end
    end

    def self.remove_local_gems(local_split, remote_split)
      local_names = gem_names(local_split)
      remote_split.reject! do |line|
        line =~ /\A([^\s]+)\s.*\z/ && local_names.include?($1)
      end
    end
  end
end

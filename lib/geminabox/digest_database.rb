require 'sqlite3'
require 'fileutils'

module Geminabox
  class DigestDatabase

    class << self

      include Gem::UserInteraction

      def perform
        db = new
        yield db
      rescue SQLite3::BusyException
        say "Ignoring info file digest database busy exeption"
        return nil
      rescue => e
        say "Unexpected info file digest datase error : #{e}"
        raise
      ensure
        db.close unless db.nil?
      end

    end

    def initialize
      path = File.join(Geminabox.data, "database/digests.db")
      FileUtils.mkdir_p(File.dirname(path))
      @db = SQLite3::Database.new(path)
      create_table unless table_exists?
    end

    def close
      @db.close
    end

    def empty?
      rows = @db.execute "SELECT count(*) FROM digests"
      rows.first.first == 0
    end

    def table_exists?
      @db.table_info("digests").any?
    end

    def create_table
      @db.execute "CREATE TABLE IF NOT EXISTS digests (gem VARCHAR(256) NOT NULL PRIMARY KEY, digest CHAR(32) NOT NULL)"
    end

    def dump_db
      @db.execute("SELECT * FROM digests").each { |row| puts row.inspect }
    end

    def get_digest(gem)
      rows = @db.execute "SELECT digest from digests WHERE gem=?", gem
      rows.first&.first
    end

    def add_digest(gem, digest)
      @db.execute "INSERT OR REPLACE INTO digests (gem, digest) VALUES (?,?)", gem, digest
    end

    def remove_digest(gem)
      @db.execute "DELETE FROM digests WHERE gem=?", gem
    end

    def refresh(new_versions, old_versions)
      @db.transaction do
        new_version_info = VersionInfo.new
        new_version_info.content = new_versions
        new_version_info.digests.each do |gem, digest|
          add_digest(gem, digest)
        end

        return unless old_versions

        old_version_info = VersionInfo.new
        old_version_info.content = old_versions
        old_version_info.digests.each_key do |gem|
          remove_digest(gem) unless new_version_info.digests.has_key?(gem)
        end
      end
    end
  end
end

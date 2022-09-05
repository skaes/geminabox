require_relative '../../test_helper'

module Geminabox
  class DigestDatabaseTest < Minitest::Test
    def setup
      clean_data_dir
      @db = DigestDatabase.new
    end

    def test_database_is_initially_empty
      assert @db.empty?
    end

    def test_digests_can_be_added_and_removed
      @db.add_digest("foo", "bar")
      assert_equal("bar", @db.get_digest("foo"))
      @db.add_digest("foo", "baz")
      assert_equal("baz", @db.get_digest("foo"))
      @db.remove_digest("foo")
      assert_nil @db.get_digest("foo")
    end

    def test_refresh_inserts_new_digests
      @db.refresh(new_versions, nil)
      assert_equal "digest1new", @db.get_digest("gem1")
      assert_equal "digest2new", @db.get_digest("gem2")
    end

    def test_refresh_updates_existing_digests_and_removes_obsolete_ones
      @db.add_digest("gem1", "digest1old")
      assert_equal "digest1old", @db.get_digest("gem1")
      @db.add_digest("gem3", "digest3old")
      assert_equal "digest3old", @db.get_digest("gem3")
      @db.refresh(new_versions, old_versions)
      assert_equal "digest1new", @db.get_digest("gem1")
      assert_equal "digest2new", @db.get_digest("gem2")
      assert_nil @db.get_digest("gem3")
    end

    def test_perform_returns_the_value_of_the_query
      digest = DigestDatabase.perform do |db|
        db.add_digest("foo", "ohohoh")
        db.get_digest("foo")
      end
      assert_equal "ohohoh", digest
    end

    def test_perform_returns_nil_if_the_database_is_busy
      digest = DigestDatabase.perform do |db|
        raise SQLite3::BusyException
      end
      assert_nil digest
    end

    def test_perform_raises_exceptions_other_than_the_db_being_busy
      assert_raises do
        DigestDatabase.perform { raise "other" }
      end
    end

    def new_versions
      VersionInfo.new.tap do |info|
        info.content = info.version_file_preamble + "gem1 1.0.0,2.0.0 digest1new\ngem2 1.0.0 digest2new\n"
      end.content
    end

    def old_versions
      VersionInfo.new.tap do |info|
        info.content = info.version_file_preamble + "gem1 1.0.0 digest1old\ngem3 1.0.0 digest3old\n"
      end.content
    end
  end
end

require_relative '../test_helper'
require 'rack/test'

class ProxyDownloadsTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    clean_data_dir
    Geminabox.rubygems_proxy = true
  end

  def teardown
    Geminabox.rubygems_proxy = false
  end

  def app
    Geminabox::Server
  end

  test "can download remote gems" do
    v1_gem = GemFactory.gem_file("foo", version: "1.0.0")
    stub_request(:get, "https://rubygems.org/gems/foo-1.0.0.gem")
      .with(headers: { 'User-Agent' => /./ })
      .to_return(status: 200, body: File.binread(v1_gem), headers: {"Content-Type" => "application/octet-stream"})

    get "/gems/foo-1.0.0.gem"
    assert last_response.ok?, "unexpected response for /gems/foo-1.0.0.gem --> #{last_response.inspect}"
  end

  test "can download local gems" do
    inject_gems { |builder| builder.gem "example" }
    get "/gems/example-1.0.0.gem"
    assert last_response.ok?, "unexpected response for /gems/example-1.0.0.gem --> #{last_response.inspect}"
  end

  test "refuses to serve a remote gem that has local versions" do
    inject_gems { |builder| builder.gem "foo", version: "1.0.0" }
    Geminabox::CompactIndexer.new.reindex

    v2_gem = GemFactory.gem_file("foo", version: "2.0.0")
    stub_request(:get, "https://rubygems.org/gems/foo-2.0.0.gem")
      .with(headers: { 'User-Agent' => /./ })
      .to_return(status: 200, body: File.binread(v2_gem), headers: {"Content-Type" => "application/octet-stream"})

    get "/gems/foo-2.0.0.gem"
    assert last_response.not_found?, "unexpected response for /gems/foo-2.0.0.gem --> #{last_response.inspect}"
  end

  test "can download remote gem specs from the quick index" do
    stub_request(:get, "https://rubygems.org/quick/Marshal.4.8/foo-1.0.0.gemspec.rz")
      .with(headers: { 'User-Agent' => /./ })
      .to_return(status: 200, body: "foo-1.0.0.gemspec.rz", headers: {})

    get "/quick/Marshal.4.8/foo-1.0.0.gemspec.rz"
    assert last_response.ok?, "unexpected response for /quick/Marshal.4.8/foo-1.0.0.gemspec.rz --> #{last_response.inspect}"
  end

  test "can download the specs indexes" do
    %w[specs latest_specs prerelease_specs].each do |index|
      stub_request(:get, "https://rubygems.org/#{index}.4.8.gz")
        .with(headers: { 'User-Agent' => /./ })
        .to_return(status: 200, body: index, headers: {})

      get "/#{index}.4.8.gz"
      assert last_response.ok?, "unexpected response for /#{index}.4.8.gz --> #{last_response.inspect}"
    end
  end
end

require_relative '../../test_helper'
require 'rack/test'

class LargeGemListSpec < Geminabox::TestCase
  include Capybara::DSL

  test "more than 5 versions of the same gem" do
    Capybara.app = Geminabox::TestCase.app
    cache_fixture_data_dir('large_gem_list_test') do
      assert_can_push(:unrelated_gem, :version => '1.0')

      assert_can_push(:my_gem, :version => '1.0')
      assert_can_push(:my_gem, :version => '2.0')
      assert_can_push(:my_gem, :version => '3.0')
      assert_can_push(:my_gem, :version => '4.0')
      assert_can_push(:my_gem, :version => '5.0')
      assert_can_push(:my_gem, :version => '6.0')
    end

    visit url_for("/")

    assert_equal gems_on_page, my_gems(6).take(5) + %w[unrelated_gem-1.0]

    page.click_link 'Older versions...'

    6.downto(1).each do |i|
      assert_current_path("/gems/my_gem")
      assert_equal gems_on_page, my_gems(i)
      page.find('.delete-form', match: :first).find_button('delete').click
    end

    assert_current_path("/")
    assert_equal gems_on_page, %w[unrelated_gem-1.0]
  end

  def gems_on_page
    page.all('a.download').
         map{|el| el['href'] }.
         map{|url| url.split("/").last.gsub(/\.gem$/, '') }
  end

  def my_gems(num)
    (1..num).map { |i| "my_gem-#{i}.0" }.reverse
  end
end

require "test_helper"
require "net/http"
require "json"

class ControlTest < Minitest::Test
  include PipeHelpers

  def setup
    start_echo
    @pipe = Flappy.pipe(to: @echo.address, control: 0)
  end

  def call(method, path, body = nil)
    uri = URI("#{@pipe.control_url}#{path}")
    request = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
    request.body = JSON.generate(body) if body
    response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
    [response.code.to_i, response.body.to_s.empty? ? nil : JSON.parse(response.body)]
  end

  def test_state_reports_clear_skies_to_start_with
    code, state = call(:get, "/")
    assert_equal 200, code
    assert_equal "clear skies", state["describe"]
    assert_nil state["level"]
  end

  def test_a_test_can_sign_in_clear_then_start_the_weather
    assert_equal "hello", round_trip("hello")

    code, state = call(:post, "/level/the_tunnel?speed=50")
    assert_equal 200, code
    assert_equal "the_tunnel", state["level"]
    assert_equal :the_tunnel, @pipe.playing.name

    code, state = call(:post, "/clear")
    assert_equal 200, code
    assert_nil state["level"]
    assert_predicate @pipe.conditions, :clear?
  end

  def test_offline_and_stall_switches
    call(:post, "/offline")
    assert @pipe.conditions.offline
    call(:post, "/stall")
    assert @pipe.conditions.stall
    call(:post, "/clear")
    assert_predicate @pipe.conditions, :clear?
  end

  def test_conditions_can_be_set_from_json
    code, state = call(:post, "/conditions", { latency: 250, up_kbps: 64 })
    assert_equal 200, code
    assert_equal 250, state["conditions"]["latency"]
    assert_equal 64, @pipe.conditions.up_kbps
  end

  def test_unknown_levels_and_routes_are_rejected
    code, = call(:post, "/level/nope")
    assert_equal 422, code
    code, = call(:get, "/nope")
    assert_equal 404, code
    code, = call(:post, "/conditions", { bogus: 1 })
    assert_equal 422, code
  end

  def test_allows_calls_from_a_browser_page
    uri = URI(@pipe.control_url)
    response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(Net::HTTP::Options.new("/")) }
    assert_equal "204", response.code
    assert_equal "*", response["Access-Control-Allow-Origin"]
  end
end

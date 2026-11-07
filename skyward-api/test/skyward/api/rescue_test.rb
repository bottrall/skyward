# frozen_string_literal: true

require "test_helper"

describe Skyward::API::Rescue do
  let(:trail) { [] }
  let(:logger) do
    Struct.new(:trail) do
      def info(message) = trail << [:log, JSON.parse(message, symbolize_names: true)]
    end.new(trail)
  end
  let(:on_error) { ->(exception, env) { trail << [:report, exception, env] } }
  let(:development) { false }
  let(:error_message) { "todo 42 is secret" }
  let(:error) { RuntimeError.new(error_message).tap { |raised| raised.set_backtrace(["todos.rb:7"]) } }
  let(:failing) { ->(_env) { raise error } }
  let(:problem) { { type: "about:blank", title: "Internal Server Error", status: 500, request_id: "abc-123" } }
  let(:logged) do
    {
      level: "error",
      request_id: "abc-123",
      class: "RuntimeError",
      message: error_message,
      backtrace: ["todos.rb:7"]
    }
  end
  let(:env) { { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/todos/42", "skyward.request_id" => "abc-123" } }

  def rescued(app) = Skyward::API::Rescue.new(app, logger:, on_error:, development:)

  def body(response) = JSON.parse(response.last.join, symbolize_names: true)

  it "is frozen" do
    assert_predicate rescued(failing), :frozen?
  end

  describe "#call" do
    it "returns the app's response, even an error it returns, without logging or reporting it" do
      response = [404, { "content-type" => "application/problem+json" }, ["{}"]]

      assert_equal [response, []], [rescued(->(_env) { response }).call(env), trail]
    end

    it "leaves an exception that isn't a StandardError alone" do
      assert_raises(Interrupt) { rescued(->(_env) { raise Interrupt }).call(env) }
    end

    it "answers an exception with a 500 problem that carries the request ID but not the exception" do
      status, headers, = response = rescued(failing).call(env)

      assert_equal [500, { "content-type" => "application/problem+json" }, problem], [status, headers, body(response)]
    end

    it "logs the exception as a JSON line, then reports it with the env" do
      rescued(failing).call(env)

      assert_equal [[:log, logged], [:report, error, env]], trail
    end

    it "answers HEAD with an empty body, even if the app rewrites the method" do
      rewrite = lambda do |request|
        request["REQUEST_METHOD"] = "GET"
        raise error
      end

      assert_equal [500, { "content-type" => "application/problem+json" }, []],
                   rescued(rewrite).call(env.merge("REQUEST_METHOD" => "HEAD"))
    end

    describe "with no logger" do
      let(:logger) { nil }

      it "still reports the exception and answers 500" do
        status = rescued(failing).call(env).first

        assert_equal [500, [[:report, error, env]]], [status, trail]
      end
    end

    describe "with no hook" do
      let(:on_error) { nil }

      it "still logs the exception and answers 500" do
        status = rescued(failing).call(env).first

        assert_equal [500, [[:log, logged]]], [status, trail]
      end
    end

    describe "with a hook that raises" do
      let(:hook_error) { IOError.new("reporter is down").tap { |raised| raised.set_backtrace(["reporter.rb:3"]) } }
      let(:on_error) { ->(_exception, _env) { raise hook_error } }

      it "logs the hook's exception too, and still answers the original 500" do
        response = rescued(failing).call(env)
        hook_logged = { **logged, class: "IOError", message: "reporter is down", backtrace: ["reporter.rb:3"] }

        assert_equal [problem, [[:log, logged], [:log, hook_logged]]], [body(response), trail]
      end
    end

    describe "with a message that isn't valid UTF-8" do
      let(:error_message) { "no todo \xFF" }

      it "logs it scrubbed, reports it, and still answers the 500" do
        status = rescued(failing).call(env).first

        assert_equal [500, [[:log, { **logged, message: "no todo �" }], [:report, error, env]]], [status, trail]
      end
    end

    describe "in development" do
      let(:development) { true }

      it "adds the exception's class, message and backtrace to the 500" do
        expected = { detail: "RuntimeError: todo 42 is secret", backtrace: ["todos.rb:7"] }

        assert_equal expected, body(rescued(failing).call(env)).slice(:detail, :backtrace)
      end

      describe "with a message that isn't valid UTF-8" do
        let(:error_message) { "no todo \xFF" }

        it "scrubs it from the detail" do
          assert_equal "RuntimeError: no todo �", body(rescued(failing).call(env))[:detail]
        end
      end
    end
  end
end

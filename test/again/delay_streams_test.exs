# Portions of this code are derived from ElixirRetry
# Project URL: https://github.com/safwank/ElixirRetry
# Original file URL: https://github.com/safwank/ElixirRetry/blob/61c3c1bc0825bebf798f97f6d484f59b4882e22b/test/retry/delay_streams_test.exs
# Copyright 2014 Safwan Kamarrudin
# Licensed under the Apache License, Version 2.0
#
# Changes made:
#   - Renamed module to Again.DelayStreamsTest

defmodule Again.DelayStreamsTest do
  use ExUnit.Case, async: true

  doctest Again.DelayStreams, import: true

  import Again.DelayStreams

  describe "exponential_backoff/1" do
    test "returns exponentially increasing delays starting with default initial delay" do
      assert exponential_backoff() |> Enum.take(5) == [10, 20, 40, 80, 160]
    end

    test "returns exponentially increasing delays starting with given initial delay" do
      assert exponential_backoff(100) |> Enum.take(5) == [100, 200, 400, 800, 1600]
    end

    test "doesn't raise arithmetric error for large streams" do
      assert exponential_backoff(100)
             |> cap(30_000)
             |> Enum.take(10_000)
             |> Enum.count() == 10_000
    end

    test "allows the factor to be configurable" do
      assert exponential_backoff(31, 1.5) |> Enum.take(5) == [31, 47, 71, 107, 161]
      assert exponential_backoff(1, 1.5) |> Enum.take(5) == [1, 2, 3, 5, 8]
    end
  end

  describe "jitter/1" do
    test "returns delays with jitter" do
      assert exponential_backoff(100) |> jitter() |> Enum.take(5) != [10, 20, 40, 80, 160]
    end

    test "returns 0 when given 0 or less" do
      assert [0, -1]
             |> Stream.cycle()
             |> jitter()
             |> Enum.take(2) == [0, 0]
    end
  end

  describe "linear_backoff/2" do
    test "returns linearly increasing delays when factor is more than 0" do
      assert linear_backoff(500, 2) |> Enum.take(5) == [500, 502, 504, 506, 508]
    end

    test "returns constant delays when factor is 0" do
      assert linear_backoff(500, 0) |> Enum.take(5) == [500, 500, 500, 500, 500]
    end
  end

  describe "constant_backoff/1" do
    test "returns constant delays with default delay" do
      assert constant_backoff()
             |> Enum.take(5)
             |> Enum.all?(&(&1 == 100))
    end

    test "returns constant delays with given initial delay" do
      initial_delay = 150

      assert constant_backoff(initial_delay)
             |> Enum.take(5)
             |> Enum.all?(&(&1 == 150))
    end
  end

  describe "cap/2" do
    test "caps delay streams to a maximum" do
      assert exponential_backoff()
             |> cap(100)
             |> Stream.take(10)
             |> Enum.all?(&(&1 <= 100))
    end
  end

  describe "expiry/3" do
    test "limits lifetime" do
      {elapsed, _} =
        :timer.tc(fn ->
          [50]
          |> Stream.cycle()
          |> expiry(100)
          |> Enum.each(&:timer.sleep/1)
        end)

      assert_in_delta elapsed / 1_000, 100, 10
    end

    test "doesn't mess up delays" do
      assert exponential_backoff() |> Enum.take(5) ==
               exponential_backoff() |> expiry(1_000) |> Enum.take(5)
    end

    test "sets a configurable minimum for the last delay" do
      assert linear_backoff(20, 2)
             |> expiry(100, 10)
             |> Enum.map(fn delay ->
               :timer.sleep(50)
               delay
             end)
             |> Enum.min() >= 10
    end

    test "stops before the expiry is reached, if there are no elements left in the delay stream" do
      assert exponential_backoff() |> Stream.take(5) |> expiry(1_000) |> Enum.count() == 5
    end

    test "evaluates expiry at runtime of the stream, rather than execution time of expiry/3" do
      delay_stream =
        [50]
        |> Stream.cycle()
        |> expiry(75, 50)

      assert Enum.count(delay_stream, fn delay -> :timer.sleep(delay) end) == 2

      # If the expiry time is determined when `expiry/3` is executed, we will
      # already be past it (due to all the sleeps performed previously) and jump
      # out after the first run.
      assert Enum.count(delay_stream, fn delay -> :timer.sleep(delay) end) == 2
    end
  end

  describe "randomize/2" do
    test "randomizes streams with default proportion" do
      delays =
        [50]
        |> Stream.cycle()
        |> randomize
        |> Enum.take(100)

      Enum.each(delays, fn delay ->
        assert_in_delta delay, 50, 50 * 0.1 + 1
        delay
      end)

      assert Enum.any?(delays, &(&1 != 500))
    end

    test "randomizes streams with given proportion" do
      delays =
        [50]
        |> Stream.cycle()
        |> randomize(0.2)
        |> Enum.take(100)

      Enum.each(delays, fn delay ->
        assert_in_delta delay, 50, 50 * 0.2 + 1
        delay
      end)

      assert Enum.any?(delays, &(abs(&1 - 50) > 50 * 0.1))
    end

    test "returns 0 when given 0 or less" do
      assert [0, -1]
             |> Stream.cycle()
             |> randomize()
             |> Enum.take(2) == [0, 0]
    end
  end
end

# Portions of this code are derived from ElixirRetry
# Project URL: https://github.com/safwank/ElixirRetry
# Original file URL: https://github.com/safwank/ElixirRetry/blob/61c3c1bc0825bebf798f97f6d484f59b4882e22b/lib/retry/delay_streams.ex
# Copyright 2014 Safwan Kamarrudin
# Licensed under the Apache License, Version 2.0
#
# Changes made:
#   - Renamed module to Again.DelayStreams
#   - Adjusted documentation, added doctests and examples

defmodule Again.DelayStreams do
  @moduledoc """
  Functions to produce or transform streams of delay values.

  The design and implementation of these delay streams are derived
  from [ElixirRetry](https://github.com/safwank/ElixirRetry) project
  made by Safwan Kamarrudin and other [contributors](https://github.com/safwank/ElixirRetry/graphs/contributors).
  """

  @type factor() :: pos_integer() | float()

  @doc """
  Returns a stream of delays that increase exponentially.

  Resulting values are rounded with `Kernel.round/1` in case floating point factor is used.

  ## Examples

      iex> exponential_backoff() |> Enum.take(5)
      [10, 20, 40, 80, 160]

      iex> 100 |> exponential_backoff(1.5) |> Enum.take(5)
      [100, 150, 225, 338, 507]
  """
  @spec exponential_backoff(pos_integer(), factor()) :: Enumerable.t()
  def exponential_backoff(initial_delay \\ 10, factor \\ 2) do
    Stream.unfold(initial_delay, fn last_delay ->
      {last_delay, round(last_delay * factor)}
    end)
  end

  @doc """
  Returns a stream in which each element of `delays` is randomly adjusted to a number
  between 1 and the original delay.

  ## Examples

      # Without jitter
      iex> 10 |> linear_backoff(10) |> Enum.take(5)
      [10, 20, 30, 40, 50]

      # With jitter
      10 |> linear_backoff(10) |> jitter() |> Enum.take(5)
      [8, 14, 28, 27, 15]
  """
  @spec jitter(Enumerable.t()) :: Enumerable.t()
  def jitter(delays) do
    Stream.map(delays, fn delay ->
      delay
      |> trunc
      |> random_uniform
    end)
  end

  @doc """
  Returns a stream of delays that increase linearly.

  Resulting values are rounded with `Kernel.round/1` in case floating point factor is used.

  ## Examples

      iex> 10 |> linear_backoff(10) |> Enum.take(5)
      [10, 20, 30, 40, 50]

      iex> 100 |> linear_backoff(50) |> Enum.take(5)
      [100, 150, 200, 250, 300]
  """
  @spec linear_backoff(pos_integer(), factor()) :: Enumerable.t()
  def linear_backoff(initial_delay, factor) do
    Stream.unfold(0, fn failures ->
      next_d = initial_delay + round(failures * factor)
      {next_d, failures + 1}
    end)
  end

  @doc """
  Returns a constant stream of delays.

  ## Examples

      iex> Enum.take(constant_backoff(), 5)
      [100, 100, 100, 100, 100]

      iex> 250 |> constant_backoff() |> Enum.take(5)
      [250, 250, 250, 250, 250]
  """
  @spec constant_backoff(pos_integer()) :: Enumerable.t()
  def constant_backoff(delay \\ 100) do
    Stream.repeatedly(fn -> delay end)
  end

  @doc """
  Returns a stream in which each element of `delays` is randomly adjusted no more than `proportion` of the delay.

  ## Examples

      100 |> linear_backoff(50) |> randomize() |> Enum.take(5)
      [102, 141, 203, 226, 272]

      100 |> linear_backoff(50) |> randomize(0.5) |> Enum.take(5)
      [130, 135, 106, 317, 191]
  """
  @spec randomize(Enumerable.t(), float()) :: Enumerable.t()
  def randomize(delays, proportion \\ 0.1) do
    Stream.map(delays, fn d ->
      max_delta = round(d * proportion)
      shift = random_uniform(2 * max_delta) - max_delta

      case d + shift do
        n when n <= 0 -> 0
        n -> n
      end
    end)
  end

  @doc """
  Returns a stream that is the same as `delays` except that the delays never exceed `max`.

  This allow capping the delay between attempts to some max value.

  ## Examples

      # Uncapped 
      iex> 100 |> linear_backoff(100) |> Enum.take(5)
      [100, 200, 300, 400, 500]
      # Capped 
      iex> 100 |> linear_backoff(100) |> cap(250) |> Enum.take(5)
      [100, 200, 250, 250, 250]
  """
  @spec cap(Enumerable.t(), pos_integer()) :: Enumerable.t()
  def cap(delays, max) do
    Stream.map(
      delays,
      fn
        d when d <= max -> d
        _ -> max
      end
    )
  end

  @doc """
  Returns a delay stream that is the same as `delays` except it limits the total life span of the stream to `time_budget`.

  This calculation takes the execution time of the block being retried into account.

  The execution of the code within the block will not be interrupted, so
  the total time of execution may run over the `time_budget` depending on how
  long a single try will take.

  Optionally, you can specify a minimum delay so the smallest value doesn't go
  below the threshold.

  ## Examples

      100
      |> constant_backoff()
      |> expiry(500)
      |> Stream.each(&Process.sleep/1)
      |> Enum.sum()
      500
  """
  @spec expiry(Enumerable.t(), pos_integer(), pos_integer()) :: Enumerable.t()
  def expiry(delays, time_budget, min_delay \\ 100) do
    Stream.resource(
      fn -> {delays, :os.system_time(:milli_seconds) + time_budget} end,
      fn
        :at_end -> {:halt, :at_end}
        {remaining_delays, end_t} -> reduce_delays(remaining_delays, end_t, min_delay)
      end,
      fn _ -> :noop end
    )
  end

  defp reduce_delays(remaining_delays, end_t, min_delay) do
    case Enum.take(remaining_delays, 1) do
      [preferred_delay] ->
        now_t = :os.system_time(:milli_seconds)
        remaining_t = Enum.max([end_t - now_t, min_delay])

        if preferred_delay >= remaining_t or remaining_t == min_delay do
          # one last try before time budget is exceeded
          {[remaining_t], :at_end}
        else
          # default
          {[preferred_delay], {Stream.drop(remaining_delays, 1), end_t}}
        end

      _ ->
        # reached end of stream - no more tries
        {:halt, :at_end}
    end
  end

  defp random_uniform(n) when n <= 0, do: 0
  defp random_uniform(n), do: :rand.uniform(n)
end

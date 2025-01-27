defmodule Again do
  @moduledoc """
  Provides retry functionality with configurable backoff strategies.

  Again allows you to easily retry operations that may fail temporarily, such as network 
  requests or distributed system operations. It supports both simple retries and 
  stateful retries with an accumulator.

  Again is heavily inspired by the [Retry](https://hexdocs.pm/retry) library.
  For details on the design decisions, see [Problems with Retry](Problems with Retry.md). 
  If you're migrating from Retry, check out the [Migrating from Retry](Migrating from Retry.md).

  ## Basic usage

  The most common use case is retrying a function until it succeeds:

      import Again.DelayStreams

      Again.retry(
        fn -> make_network_call() end,
        &match?({:error, _}, &1),
        Stream.take(exponential_backoff(), 5)
      )

  ## Features

    * Composable backoff strategies via `Again.DelayStreams`
    * Flexible retry predicates - specify precisely what conditions to retry
    * Accumulator support - maintain state between retry attempts

  ## Stateful retries

  For operations that need to maintain state between attempts, use `retry_with_acc/4`:

      Again.retry_with_acc(
        fn attempts -> {network_call(), attempts + 1} end,
        fn result, _attempts -> match?({:error, _}, result) end,
        0,
        Stream.take(constant_backoff(), 5)
      )
  """

  @sleeper Application.compile_env(:again, :sleeper, Process)

  @typedoc """
  Return value from the function being retried.
  """

  @type result :: term()

  @typedoc """
  Accumulator used in `retry_with_acc/4` function.
  """
  @type acc :: term()

  @typedoc """
  Non-negative integer representing milliseconds to wait between retry attempts.
  """
  @type delay :: non_neg_integer()

  @typedoc """
  Sequence of delays between retry attempts.
  """
  @type delays :: Enumerable.t(delay())

  @doc """
  Retries a function until it succeeds or runs out of retry attempts.

  Takes a function to execute, a predicate function that determines if retry is needed, 
  and a collection of delay values that determine how much time should pass between attempts.

  The first attempt is made immediately. Delays between subsequent attempts are determined by the provided `delays`.

  ## Parameters

  * `function` - Zero arity function to be called.
  * `should_retry_fn` - Predicate function that receives the result of `function` invocation. Should return a `t:boolean/0` indicating whether retry is needed.
  * `delays` - An enumerable of integers representing milliseconds between retry attempts.

  Returns the result of the last `function` invocation after retries are exhausted or success is achieved.

  ## Examples

      # Retry with exponential backoff, limited to 5 attempts
      Again.retry(
        fn -> network_call() end,
        &match?({:error, _}, &1),
        Stream.take(exponential_backoff(), 5)
      )

      # Retry only specific errors with 100ms delays, stopping after 1 second of attempts
      Again.retry(
        fn -> network_call() end,
        &match?({:error, reason} when reason in @reasons, &1)
        100 |> constant_backoff() |> expiry(1_000)
      )
  """
  @spec retry((-> result()), (result() -> boolean()), delays()) :: result()
  def retry(function, should_retry_fn, delays) do
    [0]
    |> Stream.concat(delays)
    |> Enum.reduce_while(nil, fn delay, _acc ->
      @sleeper.sleep(delay)

      result = function.()

      case should_retry_fn.(result) do
        true -> {:cont, result}
        false -> {:halt, result}
      end
    end)
  end

  @doc """
  Retries a function until it succeeds or runs out of retry attempts passing accumulator between attempts.

  Takes a function to execute, a predicate function that determines if retry is needed,
  an initial accumulator value, and a collection of delay values that determine how much time should pass between attempts.

  The first attempt is made immediately. Delays between subsequent attempts are determined by the provided `delays`.

  ## Parameters

  * `function` - Function that takes an accumulator and returns a tuple of `{result, new_accumulator}`.
  * `should_retry_fn` - Predicate function that receives the result and accumulator. Should return a `t:boolean/0` indicating whether retry is needed.
  * `acc` - Initial accumulator value.
  * `delays` - An enumerable of integers representing milliseconds between retry attempts.

  Returns a tuple containing the result of the last `function` invocation and final accumulator value after retries are exhausted or success is achieved.

  ## Examples

      # Retry with exponential backoff, tracking attempt count
      Again.retry_with_acc(
        fn count -> {network_call(), count + 1} end,
        fn result, _count -> match?({:error, _}, result) end,
        0,
        Stream.take(exponential_backoff(), 5)
      )

      # Retry with constant backoff, accumulating errors
      Again.retry_with_acc(
        fn errors -> 
          case network_call() do
            {:error, reason} = err -> {err, [reason | errors]}
            success -> {success, errors}
          end
        end,
        fn result, _errors -> match?({:error, _}, result),
        [],
        Stream.take(constant_backoff(), 5)
      )
  """
  @spec retry_with_acc(
          (acc() -> {result(), acc()}),
          (result(), acc() -> boolean()),
          acc(),
          delays()
        ) :: {result(), acc()}
  def retry_with_acc(function, should_retry_fn, acc, delays) do
    [0]
    |> Stream.concat(delays)
    |> Enum.reduce_while({nil, acc}, fn delay, {_result, acc} ->
      @sleeper.sleep(delay)

      next_value = {result, acc} = function.(acc)

      case should_retry_fn.(result, acc) do
        true -> {:cont, next_value}
        false -> {:halt, next_value}
      end
    end)
  end
end

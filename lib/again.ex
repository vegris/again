defmodule Again do
  @moduledoc """
  Documentation for `Again`.
  """

  @sleeper Application.compile_env(:again, :sleeper, Process)

  @type result :: term()
  @type acc :: term()
  @type delay :: non_neg_integer()
  @type delays :: Enumerable.t(delay())

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

# Problems with Retry

This document highlights suboptimal decisions made in the __Retry__ library. The analysis is based on version __0.18.0__, which is the latest version as of early 2025. Future versions of the library may address some or all of these issues. I will update this document accordingly when they do.

> #### Info {: .info}
>
> I would like to point out that the __Retry__ library was created almost a decade ago (version 0.1.0 released on May 4, 2016), and there was no clear consensus then on many things that seem obvious today.

## Retry conditions

Retry logic is typically implemented when making network calls - to databases, Redis, or external HTTP services. Possible responses from such calls can be categorized into three types:

1. Service received the request, understood it, and executed it
2. Service received the request but either didn't understand it or refused to execute it
3. Service never received the request

Only the first response can be considered successful, which is usually represented in Elixir as `:ok` or `{:ok, result}`. The other two categories are represented as `{:error, reason}`, where programmers must to examine the `reason` field to determine the specific category.

Here's a real example from the `command/3` function in [Redix](https://hexdocs.pm/redix/Redix.html#command/3) library:

> The return value is `{:ok, response}` if the request is successful and the
  response is not a Redis error. `{:error, reason}` is returned in case there's
  an error in the request (such as losing the connection to Redis in between the
  request). `reason` can also be a `Redix.Error` exception in case Redis is
  reachable but returns an error (such as a type error).

Here, `{:ok, response}` is a successful result, `{:error, %Redix.Error{}}` means that Redis received the request but refused to execute it, and all other `{:error, reason}` cases indicate that Redis did not receive the request.

In the context of retries, it's important to note that it only makes sense to retry requests in the third category.

__Retry__ doesn't provide an easy way to express this. This code will trigger retries even if the initial command is formed incorrectly:

```elixir
retry with: delays do
  Redix.command(conn, command)
end
```

A working approach for __Retry__ requires converting the relevant error category in the `do` block to a separate one and configuring the library to retry only that category:

```elixir
retry with: delays, atoms: [:retryable] do
  case Redix.command(conn, command) do
    {:error, reason} when not is_struct(reason, Redix.Error) ->
      {:retryable, reason}

    result ->
      result
  end
  else
    {:retryable, reason} -> {:error, reason}
  end
```

With __Again__, programmers can precisely configure which errors should trigger retries:

```elixir
Again.retry(
  fn -> Redix.command(conn, command) end,
  &match?({:error, reason} when not is_struct(reason, Redix.Error), &1),
  delays
)
```

## Exception handling

In addition to atoms and tuples, __Retry__ can trigger retries based on exception types raised by the specified block of code.

> ... if the block raises any of the exceptions specified in `rescue_only`, a retry will be attempted. Other exceptions will not be retried. If `rescue_only` is not specified, it defaults to `[RuntimeError]`.

_from [Retry](https://hexdocs.pm/retry/Retry.html#retry/2) docs_

Using exceptions to control program flow can be considered [an anti-pattern](`e:elixir:design-anti-patterns.html#exceptions-for-control-flow`) (although the anti-pattern wording doesn't definitively classify __Retry__ as such).

__Retry__'s exception handling implementation has several specific issues.

### Rescue RuntimeError as default

Using `RuntimeError` as the default is problematic because this exception is typically used as a runtime assertion. For example, code could validate its configuration and raise this exception if it detects an error:

```elixir
def call_service(opts) do
    if opts[:option_1] && opts[:option_2] do
        raise "Passing :option_1 and :option_2 together is invalid"
    end
end
```

Retrying this code with the same configuration is pointless because the result won't change.

To avoid this behavior, programmers need to pass an empty list to the `rescue_only` option.

### Loss of stacktrace

__Retry__ "loses" the stacktrace for exceptions listed in `rescue_only`.

For example, this code:
```elixir
Mix.install([:retry])

defmodule M do
  use Retry

  def run do
    retry with: [100] do
      call_service()
    end
  end

  defp call_service do
    if :erlang.phash2(1, 1) == 0 do
      raise "oops!"
    end
  end 
end

M.run()
```
will return an incomplete stacktrace
```sh
$ elixir script.exs        
** (RuntimeError) oops!
    script.exs:7: M.run/0
    script.exs:19: (file)
```

Using `rescue_only: []` allows getting the full stacktrace:
```sh
$ elixir script.exs
** (RuntimeError) oops!
    script.exs:14: M.call_service/0
    script.exs:8: anonymous fn/0 in M.run/0
    (elixir 1.18.1) lib/enum.ex:4964: Enumerable.List.reduce/3
    (elixir 1.18.1) lib/stream.ex:1041: Stream.do_transform_inner_list/7
    (elixir 1.18.1) lib/enum.ex:2600: Enum.reduce_while/3
    script.exs:7: M.run/0
    script.exs:19: (file)
```

## Macro usage

The __Retry__ library uses macros for its operation, generating unexpectedly large amounts of code at macro call sites.

For example, you might write:
```elixir
retry with: Stream.take(constant_backoff(), 10) do
  Enum.random([:ok, :error])
end
```

And after expanding the `retry/2` macro, you get:
```elixir
fun = fn ->
  try do
    case Enum.random([:ok, :error]) do
      {atom, _} = result ->
        if atom in [:error] do
          {:cont, result}
        else
          {:halt, result}
        end

      result ->
        if is_atom(result) and result in [:error] do
          {:cont, result}
        else
          {:halt, result}
        end
    end
  rescue
    e ->
      if e.__struct__ in [RuntimeError] do
        {:cont, {:exception, e}}
      else
        reraise e, __STACKTRACE__
      end
  end
end

(
  delays = Stream.take(constant_backoff(), 10)
  [0] |> Stream.concat(delays)
)
|> Enum.reduce_while(nil, fn delay, _last_result ->
  :timer.sleep(delay)
  fun.()
end)
|> case do
  {:exception, e} ->
    case e do
      e when is_exception(e) -> raise e
      e -> e
    end

  e = {atom, _} when atom in [:error] ->
    case e do
      e when is_exception(e) -> raise e
      e -> e
    end

  e when is_atom(e) and e in [:error] ->
    case e do
      e when is_exception(e) -> raise e
      e -> e
    end

  result ->
    case result do
      result -> result
    end
end
```

While 50 additional lines of code is not a significant concern, it should be noted that this amount of code will be generated with each new `retry/2` call. This can have a negative impact on project compilation time. Furthermore, each expanded version includes all possible error handling variants: `:error` atoms, `{:error, reason}` tuples, and exceptions. However, in practice each call likely works with only one error type.

Also, the `retry/2` macro does nothing special that can't be done by a function call (as demonstrated by __Again__), which means it is [an anti-pattern](`e:elixir:macro-anti-patterns.html#unnecessary-macros`).

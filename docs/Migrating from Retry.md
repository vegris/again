# Migrating from Retry

> #### Note {: .info}
> 
> The following examples demonstrate how to preserve exact behavior when migrating from Retry to OnceMore.
> However, you may want to consider restructuring your retry logic instead of maintaining direct equivalence.

## retry/2

```elixir
# Retry
use Retry
retry with: delays do
  call_service()
end

# OnceMore
import OnceMore.DelayStreams
OnceMore.retry(
  &call_service/0,
  &(&1 == :error or match?({:error, _reason}, &1)),
  delays
)
```

> #### RuntimeError {: .warning}
> 
> This and the following examples ignore the fact that, by default, __Retry__ rescues `RuntimeError` exception and treats it as a reason to retry. See [Problems with Retry](problems-with-retry.html#rescue-runtimeerror-as-default) for why this behavior is undesirable.

### Atoms and error tuples

> If the block returns any of the atoms specified in `atoms`, a retry will be attempted. Other atoms or atom-result tuples will not be retried. If `atoms` is not specified, it defaults to `[:error]`.

_from [Retry](https://hexdocs.pm/retry/Retry.html#retry/2) docs_

If you relied on `atoms` option you can adjust `should_retry_fn` as necessary:

```elixir
# Retry
retry with: delays, atoms: [:error, :custom_error] do
  call_service()
end

# OnceMore
@errors [:error, :custom_error]
OnceMore.retry(
  &call_service/0,
  &(&1 in @errors or match?({error, _reason} when error in @errors, &1)),
  delays
)
```

### Exceptions

> Similary, if the block raises any of the exceptions specified in `rescue_only`, a retry will be attempted. Other exceptions will not be retried. If `rescue_only` is not specified, it defaults to `[RuntimeError]`.

_from [Retry](https://hexdocs.pm/retry/Retry.html#retry/2) docs_

If you relied on __Retry__ catching exceptions, with __OnceMore__ you should catch your exceptions and translate them to values yourself:


```elixir
# Imagine call_service/0 can raise `CustomException`

# Retry
retry with: delays, rescue_only: [CustomException] do
  call_service()
end

# OnceMore
fn ->
  try do
    call_service()
  rescue
    e in CustomException -> {:error, e}
  end
end
|> OnceMore.retry(&match?({:error, _reason}, &1), delays)
# Retry raises unresolved exceptions after delays are exhausted
|> then(fn 
  {:error, e} when is_exception(e, CustomException) -> raise e
  result -> result
end)
```

### after and else

>   The `after` block evaluates only when the `do` block returns a valid value before timeout.
> On the other hand, the `else` block evaluates only when the `do` block remains erroneous after timeout.

_from [Retry](https://hexdocs.pm/retry/Retry.html#retry/2) docs_

If you relied on __Retry__ remapping your results with `after` and `else` blocks, with __OnceMore__ you should remap them yourself:

```elixir
retry with: delays do
  call_service()
after
  {:ok, _value} -> :ok
else
  {:error, _reason} -> :error
end

# OnceMore
&call_service/0
|> OnceMore.retry(&match?({:error, _reason}, &1), delays)
|> then(fn
    {:ok, _value} -> :ok 
    {:error, _reason} -> :error
end)
```

## retry_while/2

OnceMore returns both last result and accumulator while Retry returns only the accumulator.
You need to adjust return values if you want to preserve that behavior.

```elixir
# Retry
retry_while acc: 0, with: delays do
  acc ->
    case call_service() do
      %{"errors" => true} -> {:cont, acc + 1}
      result -> {:halt, result}
    end
end

# OnceMore
fn acc ->
  case call_service() do
    %{"errors" => true} -> {:error, acc + 1}
    result -> {:ok, result}
  end
end
|> OnceMore.retry_with_acc(
  fn result, _acc -> result == :error end,
  0,
  delays
)
|> then(fn
  {:ok, result} -> result
  {:error, acc} -> acc
end)
```

## wait/2

__Retry__ decides if retry is needed based on result being "falsey" (`x in [false, nil]`). You can achieve the same behavior by passing `Kernel.!/1` as a predicate to __OnceMore__.

Keep in mind that __Retry__ wraps result in `:ok/:error` tuple depending on if it's "truthy" or "falsey". You need to wrap it yourself if you want to preserve that behavior.

```elixir
# Retry
wait delays do
  get_available_service()
end

# OnceMore
&get_available_service/0
|> OnceMore.retry(&Kernel.!/1, delays)
|> then(fn result ->
  if result do
    {:ok, result}
  else
    {:error, result}
  end
end)
```

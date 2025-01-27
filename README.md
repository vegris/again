# Again

A flexible retry library for Elixir with composable backoff strategies.

Again allows you to easily retry operations that may fail temporarily, such as network 
requests or distributed system operations. It supports both simple retries and 
stateful retries with an accumulator.

## Installation

Add `again` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:again, "~> 1.0.0"}
  ]
end
```

## Features

* Composable backoff strategies via `Again.DelayStreams`
* Flexible retry predicates - specify precisely what conditions to retry
* Accumulator support - maintain state between retry attempts

## Quick start

```elixir
import Again.DelayStreams

# Basic retry with exponential backoff
Again.retry(
  fn -> make_network_call() end,
  &match?({:error, _}, &1),
  Stream.take(exponential_backoff(), 5)
)

# Retry with accumulator to track state
Again.retry_with_acc(
  fn attempts -> {network_call(), attempts + 1} end,
  fn result, _attempts -> match?({:error, _}, result) end,
  0,
  Stream.take(constant_backoff(), 5)
)

# Common delay patterns can be composed:
50                        # Start with 50ms delay
|> exponential_backoff()  # Increase exponentially
|> randomize(0.2)         # Add some randomization
|> cap(1_000)             # Cap at 1 second
|> Stream.take(5)         # Limit to 5 attempts
```

Full documentation can be found at https://hexdocs.pm/again.


## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

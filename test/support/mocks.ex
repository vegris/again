defmodule OnceMore.SendSleeper do
  @moduledoc false
  def sleep(timeout) do
    send(self(), {__MODULE__, timeout})
    :ok
  end
end

defmodule OnceMore.Callable do
  @moduledoc false
  @callback function() :: OnceMore.result()
end

defmodule OnceMore.CallableWithAcc do
  @moduledoc false
  @callback function(OnceMore.acc()) :: {OnceMore.result(), OnceMore.acc()}
end

Mox.defmock(OnceMore.CallableMock, for: OnceMore.Callable)
Mox.defmock(OnceMore.CallableWithAccMock, for: OnceMore.CallableWithAcc)

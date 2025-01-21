defmodule Again.SendSleeper do
  @moduledoc false
  def sleep(timeout) do
    send(self(), {__MODULE__, timeout})
    :ok
  end
end

defmodule Again.Callable do
  @moduledoc false
  @callback function() :: Again.result()
end

defmodule Again.CallableWithAcc do
  @moduledoc false
  @callback function(Again.acc()) :: {Again.result(), Again.acc()}
end

Mox.defmock(Again.CallableMock, for: Again.Callable)
Mox.defmock(Again.CallableWithAccMock, for: Again.CallableWithAcc)

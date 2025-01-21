defmodule AgainTest do
  use ExUnit.Case, async: true

  import Mox

  import Again.DelayStreams

  setup do
    on_exit(fn ->
      refute_received _
    end)
  end

  defp error?(result), do: result != :ok
  defp error?(result, _acc), do: result != :ok

  describe "retry/3" do
    test "does not retry successful call" do
      assert :ok = Again.retry(fn -> :ok end, &error?/1, constant_backoff())
      assert_received {Again.SendSleeper, 0}
    end

    test "retries until successful" do
      times_unsuccessful = 4
      backoff = 100

      Again.CallableMock
      |> expect(:function, times_unsuccessful, fn -> :error end)
      |> expect(:function, fn -> :ok end)

      assert :ok =
               Again.retry(
                 &Again.CallableMock.function/0,
                 &error?/1,
                 constant_backoff(backoff)
               )

      assert_received {Again.SendSleeper, 0}

      for _ <- 1..times_unsuccessful do
        assert_received {Again.SendSleeper, ^backoff}
      end
    end

    test "returns last error if unsuccessful" do
      retries = 5
      backoff = 100

      expect(Again.CallableMock, :function, retries + 1, fn -> :error end)

      assert :error =
               Again.retry(
                 &Again.CallableMock.function/0,
                 &error?/1,
                 backoff |> constant_backoff() |> Stream.take(retries)
               )

      assert_received {Again.SendSleeper, 0}

      for _ <- 1..retries do
        assert_received {Again.SendSleeper, ^backoff}
      end
    end

    test "works with regular list as delay stream" do
      list = [100, 200, 300, 400, 500]
      assert :error = Again.retry(fn -> :error end, &error?/1, list)

      for delay <- [0 | list] do
        assert_received {Again.SendSleeper, ^delay}
      end
    end

    test "works with range as delay stream" do
      range = 100..500//100
      assert :error = Again.retry(fn -> :error end, &error?/1, range)

      assert_received {Again.SendSleeper, 0}

      for delay <- range do
        assert_received {Again.SendSleeper, ^delay}
      end
    end
  end

  describe "retry_with_acc/3" do
    test "does not retry successful call" do
      assert {:ok, nil} =
               Again.retry_with_acc(
                 fn acc -> {:ok, acc} end,
                 &error?/2,
                 nil,
                 constant_backoff()
               )

      assert_received {Again.SendSleeper, 0}
    end

    test "retries until successful" do
      times_unsuccessful = 4
      backoff = 100

      Again.CallableWithAccMock
      |> expect(:function, times_unsuccessful, fn acc -> {:error, acc} end)
      |> expect(:function, fn acc -> {:ok, acc} end)

      assert {:ok, nil} =
               Again.retry_with_acc(
                 &Again.CallableWithAccMock.function/1,
                 &error?/2,
                 nil,
                 constant_backoff(backoff)
               )

      assert_received {Again.SendSleeper, 0}

      for _ <- 1..times_unsuccessful do
        assert_received {Again.SendSleeper, ^backoff}
      end
    end

    test "returns last error if unsuccessful" do
      retries = 5
      backoff = 100

      expect(Again.CallableWithAccMock, :function, retries + 1, fn acc -> {:error, acc} end)

      assert {:error, nil} =
               Again.retry_with_acc(
                 &Again.CallableWithAccMock.function/1,
                 &error?/2,
                 nil,
                 backoff |> constant_backoff() |> Stream.take(retries)
               )

      assert_received {Again.SendSleeper, 0}

      for _ <- 1..retries do
        assert_received {Again.SendSleeper, ^backoff}
      end
    end

    test "updates acc once on successful call" do
      assert {:ok, 1} =
               Again.retry_with_acc(
                 fn acc -> {:ok, acc + 1} end,
                 &error?/2,
                 0,
                 constant_backoff()
               )

      assert_received {Again.SendSleeper, 0}
    end

    test "updates acc on retries" do
      retries = 5
      backoff = 100

      expect(Again.CallableWithAccMock, :function, retries + 1, fn acc -> {:error, acc + 1} end)

      assert {:error, retries + 1} ==
               Again.retry_with_acc(
                 &Again.CallableWithAccMock.function/1,
                 &error?/2,
                 0,
                 backoff |> constant_backoff() |> Stream.take(retries)
               )

      assert_received {Again.SendSleeper, 0}

      for _ <- 1..retries do
        assert_received {Again.SendSleeper, ^backoff}
      end
    end

    test "works with regular list as delay stream" do
      list = [100, 200, 300, 400, 500]

      assert {:error, nil} =
               Again.retry_with_acc(
                 fn acc -> {:error, acc} end,
                 &error?/2,
                 nil,
                 list
               )

      for delay <- [0 | list] do
        assert_received {Again.SendSleeper, ^delay}
      end
    end

    test "works with range as delay stream" do
      range = 100..500//100

      assert {:error, nil} =
               Again.retry_with_acc(
                 fn acc -> {:error, acc} end,
                 &error?/2,
                 nil,
                 range
               )

      assert_received {Again.SendSleeper, 0}

      for delay <- range do
        assert_received {Again.SendSleeper, ^delay}
      end
    end
  end
end

%{
  configs: [
    %{
      name: "default",
      strict: true,
      checks: %{
        extra: [
          {Credo.Check.Readability.StrictModuleLayout, []}
        ]
      }
    }
  ]
}

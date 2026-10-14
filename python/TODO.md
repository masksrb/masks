# Python SDK to-do

## Security

- The SDK decides whether a store is async from its `get` method alone. A store that mixes sync and async methods fails at its first call instead of when the app starts.

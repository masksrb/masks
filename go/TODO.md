# Go SDK to-do

## Security

- `Verifier` compares a proof's `htm` to the request method without regard to case. RFC 9449 compares them exactly. No client masks knows of sends a lowercase method.

## Testing

- The avatar proxy has not served a photo against a live masks. The live run on 2026-10-12 answered 404, since the test person had no photo.

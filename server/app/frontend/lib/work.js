const BATCH = 512;
const encoder = new TextEncoder();
const solved = new Map();

function leadingZeros(digest) {
  const bytes = new Uint8Array(digest);
  let count = 0;

  for (const byte of bytes) {
    if (byte === 0) {
      count += 8;
      continue;
    }

    return count + Math.clz32(byte) - 24;
  }

  return count;
}

async function search({ nonce, bits }) {
  for (let start = 0; ; start += BATCH) {
    const digests = await Promise.all(
      Array.from({ length: BATCH }, (_, offset) =>
        crypto.subtle.digest(
          "SHA-256",
          encoder.encode(`${nonce}${start + offset}`),
        ),
      ),
    );

    const found = digests.findIndex((digest) => leadingZeros(digest) >= bits);

    if (found >= 0) return String(start + found);
  }
}

export function solve(work) {
  if (!work) return Promise.resolve(null);

  if (!solved.has(work.token)) {
    solved.set(
      work.token,
      search(work).then((counter) => ({
        work: work.token,
        work_counter: counter,
      })),
    );
  }

  return solved.get(work.token);
}

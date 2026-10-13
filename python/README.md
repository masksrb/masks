# masks for Python

`masks-client` connects a Python web app, service, or machine to a
[masks](https://masks.pages.dev) server. It signs people in to FastAPI, Django,
and Flask apps, gets tokens for a service or machine, and checks access tokens
in an API.

## Install

It needs Python 3.10 or later and imports as `masks`.

```sh
pip install masks-client
```

A web app adds the extra for its framework: `masks-client[fastapi]`,
`masks-client[django]`, or `masks-client[flask]`.

## Sign people in to a FastAPI app

```python
import os
from typing import Annotated

from fastapi import Depends, FastAPI
from masks.fastapi import Actor, Config, Masks

auth = Masks(
    Config(
        issuer=os.environ["MASKS_ISSUER"],
        resource="https://app.example.com",
        name="Catalog",
        secret=os.environ["SESSION_SECRET"],
    )
)

app = FastAPI()
auth.install(app)


@app.get("/settings")
async def settings(actor: Annotated[Actor, Depends(auth.require())]):
    return {"name": actor.name}
```

To connect the app to masks:

1. Set `MASKS_ISSUER` to your masks tenant.
2. Start the app.
3. Open `/auth/handshake` and approve the app in masks.

## Documentation

- [Python apps](https://masks.pages.dev/reference/python/) explains the
  handshake, sessions, privileges, and checking tokens.
- [FastAPI](https://masks.pages.dev/reference/python/fastapi/),
  [Django](https://masks.pages.dev/reference/python/django/), and
  [Flask](https://masks.pages.dev/reference/python/flask/) set up each framework.
- [masks-client](https://masks.pages.dev/reference/python/client/) lists every
  setting and call, including machines, DPoP, and the device flow.

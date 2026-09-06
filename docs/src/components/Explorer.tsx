import { useMemo, useState } from "react";
import { GraphiQL } from "graphiql";
import { buildSchema, getIntrospectionQuery, graphqlSync, parse } from "graphql";
import "graphiql/style.css";

const INTROSPECTION = new Set(["__schema", "__type", "__typename"]);

const OPENING = `# Everything the console asks for on its Clients page.
#
# This explorer runs against the published schema, so autocomplete, the docs
# pane and validation all work. Running a query needs a masks instance and a
# bearer carrying masks:manage — point the endpoint below at your own.

query Clients {
  clients(archived: false, limit: 10) {
    clientId
    name
    dynamic
    namespaces {
      name
      resource
      releasable
    }
  }
}
`;

type Props = { sdl: string };

/** Answers introspection from the published SDL; refuses anything that would
 *  need a real tenant, since a static site has no database behind it. */
function offline(sdl: string) {
  const schema = buildSchema(sdl);

  return async ({ query, variables, operationName }: any) => {
    let onlyIntrospection = true;

    try {
      for (const definition of parse(query).definitions) {
        if (definition.kind !== "OperationDefinition") continue;

        for (const selection of definition.selectionSet.selections) {
          if (selection.kind === "Field" && !INTROSPECTION.has(selection.name.value)) {
            onlyIntrospection = false;
          }
        }
      }
    } catch {
      // Let graphql report the syntax error below rather than guessing here.
    }

    if (!onlyIntrospection) {
      return {
        errors: [
          {
            message:
              "This explorer holds the schema, not a tenant. Point it at a masks instance with a " +
              "bearer carrying masks:manage to run a query.",
          },
        ],
      };
    }

    return graphqlSync({
      schema,
      source: query || getIntrospectionQuery(),
      variableValues: variables,
      operationName,
    });
  };
}

export default function Explorer({ sdl }: Props) {
  const [endpoint, setEndpoint] = useState("");

  const fetcher = useMemo(() => {
    if (!endpoint.trim()) return offline(sdl);

    return async ({ query, variables, operationName }: any) => {
      const response = await fetch(endpoint.trim(), {
        method: "POST",
        headers: { "content-type": "application/json" },
        credentials: "omit",
        body: JSON.stringify({ query, variables, operationName }),
      });

      return response.json();
    };
  }, [endpoint, sdl]);

  return (
    <div className="explorer">
      <label className="explorer-endpoint">
        <span>Endpoint</span>
        <input
          type="url"
          value={endpoint}
          spellCheck={false}
          placeholder="https://your-tenant.example/manage/graphql — leave empty to browse the schema"
          onChange={(event) => setEndpoint(event.target.value)}
        />
      </label>

      <div className="explorer-frame">
        <GraphiQL fetcher={fetcher} defaultQuery={OPENING} />
      </div>
    </div>
  );
}

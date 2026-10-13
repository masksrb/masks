import { useMemo } from "react";
import { GraphiQL } from "graphiql";
import { buildSchema, getIntrospectionQuery, graphqlSync, parse } from "graphql";
import "graphiql/style.css";

const INTROSPECTION = new Set(["__schema", "__type", "__typename"]);

const OPENING = `# Everything /manage asks for on its Clients page.
#
# This explorer holds the published schema, so autocomplete, the docs pane, and
# validation all work. It answers only introspection queries. Send any other
# query to your own server's /manage/graphql.

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
              "This explorer holds only the schema. Send this query to your own server's " +
              "/manage/graphql with a bearer token that carries masks:manage.",
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
  const fetcher = useMemo(() => offline(sdl), [sdl]);

  return (
    <div className="explorer">
      <GraphiQL fetcher={fetcher} defaultQuery={OPENING} />
    </div>
  );
}

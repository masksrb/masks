import * as module from "node:module";

const pattern = /^next\/(server|headers|navigation)$/;

if (module.registerHooks) {
  module.registerHooks({
    resolve(specifier, context, next) {
      return next(
        pattern.test(specifier) ? `${specifier}.js` : specifier,
        context,
      );
    },
  });
} else {
  module.register(
    `data:text/javascript,${encodeURIComponent(`
export async function resolve(specifier, context, next) {
  return next(${pattern}.test(specifier) ? specifier + ".js" : specifier, context);
}
`)}`,
  );
}

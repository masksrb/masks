import _ from "lodash-es";
import { Client, cacheExchange, fetchExchange } from "@urql/svelte";
import { Login } from "./login";

class Consumer {
  constructor(opts) {
    this.opts = opts;
    this.headers = opts.headers || {};
  }

  setHeaders(headers) {
    this.headers = { ...headers };
  }

  login(opts) {
    return new Login(opts, { consumer: this });
  }

  get graphql() {
    const url = this.opts.graphql || `${this.opts.root}/masks.graphql`;

    return new Client({
      url,
      exchanges: [cacheExchange, fetchExchange],
      fetchOptions: () => {
        return this.rewriteHeaders({});
      },
    });
  }

  rewriteHeaders(opts) {
    const rewrite = { ...opts };

    rewrite.headers = _.merge(rewrite.headers || {}, this.computedHeaders);

    return rewrite;
  }

  get computedHeaders() {
    const headers = { ...this.headers };

    if (this.opts.token) {
      headers.Authorization = `Bearer ${this.opts.token}`;
    }

    if (this.opts.csrf) {
      headers["X-CSRF-Token"] = this.opts.csrf;
    }

    return headers;
  }

  fetch(url, options) {
    return fetch(url, this.rewriteHeaders(options));
  }
}

export { Consumer };

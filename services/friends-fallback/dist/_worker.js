// SPDX-License-Identifier: GPL-3.0-or-later
// Alternate entry only; the existing service owns all identities and data.
export default {
  async fetch(request, env) {
    const response = await env.FRIENDS_SERVICE.fetch(request);
    // The service emits UTF-8 JSON. Declare it for browsers that otherwise
    // guess a legacy Chinese encoding when navigating to an API response.
    if (!/^application\/(?:json|[^\s;]+\+json)(?:\s*;|$)/i.test(response.headers.get("Content-Type") || ""))
      return response;
    const outgoing = new Response(response.body, response);
    outgoing.headers.set("Content-Type", "application/json; charset=utf-8");
    return outgoing;
  },
};

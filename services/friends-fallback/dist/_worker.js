// SPDX-License-Identifier: GPL-3.0-or-later
// Alternate entry only; the existing service owns all identities and data.
export default {
  fetch(request, env) {
    return env.FRIENDS_SERVICE.fetch(request);
  },
};

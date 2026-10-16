# grund_auth

Cookie sessions for grund applications: an opaque session token in an
`HttpOnly` cookie, a global hook that puts the `CurrentUser` of a request in
its call scope, and a same-origin check for unsafe requests.

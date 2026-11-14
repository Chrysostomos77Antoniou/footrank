// Retired debug endpoint. Kept deployed only as a stub that refuses every
// request, because the dashboard is needed to delete a function outright.
Deno.serve(() =>
  new Response(JSON.stringify({ error: "gone" }), {
    status: 410,
    headers: { "Content-Type": "application/json" },
  })
);

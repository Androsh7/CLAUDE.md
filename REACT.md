# React Code Standards

These rules stand on their own; a React-only repository does not need `python.md`. The general rules shared with it are restated here in brief:

- Every name spelled out in full: no abbreviations, no single letters, including loop variables, callback parameters, and destructured fields. One carve-out: `import { z } from "zod"` is the library's documented entry point and is the single accepted single-letter name.
- Comments are rare and say *what*, never *why*. This is deliberate and the reverse of the usual advice; follow it anyway.
- Numeric defaults and thresholds are `UPPER_SNAKE_CASE` constants, with a unit suffix when the type does not make the unit clear (`DEFAULT_REQUEST_TIMEOUT_MS`).
- Fixed sets of string values are a `const` object with `as const` (or a Zod `z.enum`), never string literals scattered through the code.
- Import at the level that keeps the name readable: a bare imported name must say what it is and where it came from.

## Commands

```bash
npm create vite@latest <app-name> -- --template react-ts   # new project
npm install                                                # sync dependencies
npx prettier --write . && npx eslint --fix .               # before every commit
npx vitest                                                 # default suite, live tests excluded
npx vitest --config vite.live.config.ts                    # live tests, explicitly
```

## Quick reference

- TypeScript always. New projects come from the Vite React TypeScript template.
- Prettier formats every file and ESLint (the template's config) catches the rest; nothing is committed unformatted or failing lint.
- `axios` for every HTTP call, behind one client module the codebase owns.
- `zod` validates every piece of data that enters the app; TypeScript types at the boundary are inferred from the schema, never written by hand.
- Function components and hooks only. No class components.
- `msw` for API tests, so the real axios and zod code runs against controlled responses.

## Project setup

- Scaffold with `npm create vite@latest <app-name> -- --template react-ts`. Do not use Create React App, a hand-rolled webpack config, or a framework unless the user asks for one.
- The generated structure stays: `src/main.tsx`, `src/App.tsx`, `index.html` at the root, `vite.config.ts`.
- Organise `src/` by feature, not by file type: `src/orders/OrderList.tsx`, `src/orders/useOrders.ts`, `src/orders/orderSchemas.ts`, not `src/components/`, `src/hooks/`, `src/types/`.
- Shared infrastructure lives in `src/lib/`: `src/lib/apiClient.ts`, `src/lib/config.ts`, `src/lib/errors.ts`.

## Formatting

- Prettier, with the config committed at the repo root, `printWidth: 120` to match Python. Run `npx prettier --write .` before any commit; the check runs in pre-commit.
- Never hand-format. If Prettier's output looks wrong, the code is wrong, not Prettier.

## Components and hooks

- Function components only, declared as `function OrderList(props: OrderListProps)`, not as arrow functions assigned to `const`, so the name appears in stack traces and React DevTools.
- One component per file; file name matches the component name in PascalCase (`OrderList.tsx`).
- Props are a named `type` (`OrderListProps`) declared directly above the component. Never inline the props type in the signature.
- Custom hooks are `use<Thing>` in their own file (`useOrders.ts`) and return a named object, not a tuple, so callers destructure by name.
- Every exported component, hook, and function gets a JSDoc comment: one imperative summary line, `@param` per argument, `@returns`, no trailing periods, no types in the comment (they are in the signature).
- No `any`. If a value's shape is unknown, it is `unknown` and gets narrowed through a Zod schema.

```tsx
type OrderListProps = {
  customerId: string;
};

/**
 * Render every order placed by one customer
 *
 * @param props.customerId - The customer whose orders to show
 * @returns The list, a loading state, or an error message
 */
export function OrderList({ customerId }: OrderListProps) {
  const { orders, isLoading, error } = useOrders(customerId);
  ...
}
```

## API calls

- All HTTP goes through `axios`. Never use `fetch` directly.
- One axios instance is created in `src/lib/apiClient.ts` with the base URL, timeout, and headers. Every other module imports that instance; nothing else calls `axios.create` or `axios.get`.
- Each feature exposes its API calls as named functions in `<feature>Api.ts` (`fetchOrders`, `createOrder`). Components never import the axios instance directly; they call these functions, usually through a hook.
- Every response is passed through a Zod schema before it is returned. An API function's return type is the schema's inferred type, so a shape change in the backend fails at the boundary, not deep in a component.
- Timeouts, base URLs, and retry counts are named constants in `src/lib/config.ts`, never literals in the call.

```ts
// src/lib/apiClient.ts
import axios from "axios";

import { API_BASE_URL, DEFAULT_REQUEST_TIMEOUT_MS } from "./config";

export const apiClient = axios.create({
  baseURL: API_BASE_URL,
  timeout: DEFAULT_REQUEST_TIMEOUT_MS,
});
```

```ts
// src/orders/orderSchemas.ts
import { z } from "zod";

export const orderSchema = z.object({
  identifier: z.string(),
  customerId: z.string(),
  totalCents: z.number().int().nonnegative(),
});

export const orderListSchema = z.array(orderSchema);

export type Order = z.infer<typeof orderSchema>;
```

```ts
// src/orders/orderApi.ts
import { apiClient } from "../lib/apiClient";
import { orderListSchema, type Order } from "./orderSchemas";

/**
 * Fetch every order placed by one customer
 *
 * @param customerId - The customer whose orders to fetch
 * @returns The orders, validated against the order schema
 */
export async function fetchOrders(customerId: string): Promise<Order[]> {
  const response = await apiClient.get(`/customers/${customerId}/orders`);
  return orderListSchema.parse(response.data);
}
```

## Validation

- Zod is the single source of truth for the shape of any data crossing a boundary: API responses, form input, URL parameters, `localStorage`, environment variables.
- Schemas live in `<feature>Schemas.ts` and are named `<thing>Schema` in camelCase. The TypeScript type is always `z.infer<typeof thingSchema>`; never declare a matching `interface` by hand.
- Use `.parse` when a failure is a bug (a response the backend promised). Use `.safeParse` when a failure is expected input (a form the user is filling in) and surface the issues to the user.
- Validate environment variables once at startup in `src/lib/config.ts` with a Zod schema over `import.meta.env`, and export the parsed result. Nothing else reads `import.meta.env`.

## Error handling

- Define the app's error types in `src/lib/errors.ts`: one base `class AppError extends Error` and a subclass per failure the UI treats differently (`NetworkError`, `NotFoundError`, `ValidationError`). Set `this.name` in each constructor so it survives serialisation.
- Translate at the boundary. `<feature>Api.ts` catches `axios.isAxiosError(error)` and `ZodError` and rethrows an `AppError` subclass with `{ cause: error }`. Nothing above the API layer ever sees an axios or zod error.
- Never swallow. A `catch` either rethrows, translates, or returns a value the caller is documented to expect. An empty `catch {}` is wrong.
- Components do not `try`/`catch`. Async state (loading, error, data) comes from the hook, and the hook exposes the `AppError` for the component to render.
- One `ErrorBoundary` at the app root for render-time errors, plus one around any subtree that should fail independently. Do not wrap every component.
- Never show a raw error message or stack to the user. Map `AppError` subclasses to user-facing copy in one place.

## Logging

- No `console.log` in committed code. `console.error` and `console.warn` are allowed only inside the error boundary and the API translation layer, where the error is being handled.
- If the app needs real logging (a reporting service), wrap it in `src/lib/logger.ts` with `debug`/`info`/`warn`/`error` and call that everywhere, so the backend can change in one place.
- Never log tokens, credentials, or full request or response bodies that might contain them.

## Testing

- Vitest with React Testing Library, tests beside the file they cover as `<Name>.test.tsx`.
- Don't mock what you don't own: prefer the library's own test tooling, then an adapter this codebase owns with a hand-written fake, and never patch a third-party module's internals. For HTTP the library tooling is `msw`: it intercepts at the network layer, so the real axios instance and the real Zod parsing run against controlled responses, including error statuses and malformed payloads. Never mock `axios`, and do not fake the `<feature>Api.ts` module for API tests; that skips the parsing the test should be exercising.
- Fake a hook or module only when it wraps something `msw` cannot reach (a browser API, a third-party widget), and then fake the adapter this codebase owns around it.
- Live tests (anything hitting a real backend) are `<Name>.live.test.tsx`, excluded from the default run in `vite.config.ts` and run only via a separate `vite.live.config.ts`.
- Query the DOM the way a user would: `getByRole`, `getByLabelText`, `getByText`. Never query by class name or test id unless there is no accessible alternative.
- Assert on what the user sees, not on component internals or hook return values.

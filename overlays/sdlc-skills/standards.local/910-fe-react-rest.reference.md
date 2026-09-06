---
parent: fe-react-rest
work: —
---
# fe-react-rest — layer skeletons

## `services/<domain>Service.ts` — one typed function per endpoint

```ts
import api from './api';
import type { ApiResponse, CustomerRes, CustomerReq } from '../types';

export const getCustomerById = async (id: string | number): Promise<CustomerRes> => {
  const res = await api.get<ApiResponse<CustomerRes>>(`/customers/${id}`);
  return res.data.data;               // unwrap the envelope here, never in a component
};

export const updateCustomer = async (
  id: string | number,
  data: CustomerReq,
): Promise<CustomerRes> => {
  const res = await api.put<ApiResponse<CustomerRes>>(`/customers/${id}`, data);
  return res.data.data;
};
```

A 204 is handled here too — the service returns `null` or a typed sentinel and the hook surfaces it as
`data`, so consumers branch on `data === null`.

## `queries/<domain>Service.ts` — keys factory + hooks

```ts
export const customerKeys = {
  all: ['customers'] as const,
  lists: () => [...customerKeys.all, 'list'] as const,
  details: () => [...customerKeys.all, 'detail'] as const,
  detail: (id: string | number) => [...customerKeys.details(), String(id)] as const,
};

export function useCustomer(id: string | number | undefined) {
  return useQuery({
    queryKey: customerKeys.detail(id!),
    queryFn: () => getCustomerById(id!),
    enabled: !!id,
  });
}

export function useUpdateCustomer(customerId: string | number) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (data: CustomerReq) => updateCustomer(customerId, data),
    onSuccess: (updated) => {
      qc.setQueryData(customerKeys.detail(customerId), updated);
      qc.invalidateQueries({ queryKey: customerKeys.lists() });
    },
  });
}
```

The canonical key shape lives in `queries/_keys.ts`. Reserve the `predicate` form of
`invalidateQueries` for cross-factory fan-out; prefer narrow key invalidation everywhere else.

## Component

```tsx
const { data: customer, isLoading, error } = useCustomer(customerId);
if (isLoading) return <Spinner />;
if (error) return <ErrorAlert error={error} />;
return <CustomerCard customer={customer} />;
```

## Shared `QueryClient`

One client in `queries/core.ts`: `staleTime: 30s`, `gcTime: 5min`, queries retry twice with
exponential backoff, mutations never retry. Mock mode drops `staleTime` to 0 and disables retries.
Override at the hook level only where a query genuinely needs different behavior.

## Trap: a mutation result that gates a render

When a mutation's result decides what renders (e.g. show the payment iframe once a `clientSecret`
arrives), drive the render off **local state captured from `mutateAsync().then()`**, not off
`useMutation()`'s `data` / `isPending` / `error`.

```tsx
const m = useCreateCheckoutSession();
const [clientSecret, setClientSecret] = useState<string | null>(null);
const startedRef = useRef(false);                     // idempotency guard

useEffect(() => {
  if (!open || startedRef.current) return;
  startedRef.current = true;
  m.mutateAsync(req).then((res) => setClientSecret(res.clientSecret));
}, [open]);
```

Why, empirically: under `<React.StrictMode>` with nested auth and query providers, React Query v5's
mutation observer can drop the success notification — the request returns 2xx and the `mutateAsync`
promise resolves, while the observer's `data` stays `undefined` and `status` stays `'pending'`
forever. The promise is owned by JS and cannot be orphaned; the observer subscription can. A
fire-and-forget mutation with no render gate is fine with plain `mutate()` and hook-level `onSuccess`.

## Exception: third-party SDK hooks

The routing rule covers HTTP through the axios layer. Third-party SDK initializers and hooks (Stripe
Elements, a Maps loader) keep their own state lifecycles and live in `hooks/` or `lib/<sdk>/`.

## Common traps

- `api.get(...)` or a `services/` import inside a component — collapses the layers.
- A `services/` file importing React or `@tanstack/react-query`; a `queries/` file importing axios.
- try/catch around a hook call instead of reading its `error` field.
- Unwrapping `response.data.data` in a component.
- Testing by class or id selector rather than role/label.

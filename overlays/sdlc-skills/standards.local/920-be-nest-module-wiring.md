---
name: be-nest-module-wiring
applies-when: discipline == BE && platform == nextgen && stack == ts-nest
source: null
on-missing-source: skip
---
# be-nest-module-wiring (local — ts-nest only)

Register every provider a NestJS module owns in that module's own `@Module({ providers: [...] })`,
and reach it from anywhere else only through constructor injection of an exported provider. A sibling
service that needs a collaborator declares it as a constructor parameter; the owning module lists it
in `exports`, and the consuming module lists that module in `imports`. Never `import { FooService }
from '../foo/foo.service'` and construct or call it directly — the import is for the type in the
constructor signature only.

A provider reached outside the container gets no lifecycle, no request scope, no interceptors, and no
test double: the DI graph is the seam every unit test overrides with `overrideProvider()`. A direct
sibling import also hides a module cycle that Nest would otherwise refuse at boot, so the failure
surfaces at runtime instead of at wiring time.

**Verify:**

```bash
npm test        # a sibling collaborator must be replaceable via overrideProvider() in the module test
npm run lint
grep -rn "new [A-Z][A-Za-z]*Service(" src/ --include=*.ts | grep -v ".spec.ts"   # expect no hits
```

Read the full output and exit code; confirm the new tests ran.

Why: the layering contract in `be-layered-service` says which layer may call which. This says the call
must travel through the container that owns the object's lifetime, so the layering is enforced by
Nest's module graph rather than by convention alone.

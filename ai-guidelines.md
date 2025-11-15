# Project Guidelines

## Project Structure

- try using "nvm use", to set the correct node version. Before running any "node" app.
- [routes](src/routes) - In that directory must reside all modules, crud, backend and frontend.
- Each module must be in a group. Look that module as an example "src/routes/user". Everything about the User module must be in that directory, including unit tests and SSR (server side rendering) and backend functions. Everything! In the same directory. The only exception is End-to-End tests, which must be in "/e2e/".
- Each module must create a group on table named "group", add do table "rel_group" the user id "1" will be the administrator. On user id "1" logins, make sure that user "1" is the administrator of all modules and groups.
- Each module must have an "SoftwareItem" here "src/lib/app.ts" that is the way to users gain access to the module.
- 
- Should ignore this directory: "/stash"
- Database Schema - [schema.md](src/lib/db/schema.md) - [schema.ts](src/lib/db/schema.ts) - These files contain the data structure. Also maintain the data structure documentation using Mermaid.js. Run "pnpm db:push" to apply modifications to schema (this command need human review)
- Maintain [All Project Documentation and Specifications](./SPEC.md).
- The utility directory to avoid code repetition is "src/lib"
- [Dictionary of Terminology](./terminology.md)
- [e2e](e2e) - End-to-end testing directory — put all user journeys in this directory.
- [cleanup_chrome.sh](cleanup_chrome.sh) - This script ensures all Chrome instances are closed after running the end-to-end tests.
- Unit tests should stay alongside their pages, named ".spec.ts", following this example: [demo.spec.ts](src/routes/home/demo.spec.ts).
- [messages](messages) - All text messages in multiple languages should be placed here.
- [settings.json](project.inlang/settings.json) - Configuration for which languages the project supports and the number of languages.
- [static](static) - Static files; no AI should modify this directory.
- [.env](.env) [.env.example](.env.example) - Always keep the ".env" and ".env.example" files in sync with the same content, but mask the values in the example.

- [wrangler.jsonc](wrangler.jsonc) - This file is used for Cloudflare Workers; AIs should check whether the variables match those in ".env".

- [assets](src/lib/assets) - Directory where the server will store raw files. Probably no AI will use this directory.
- [paraglide](src/lib/paraglide) - Ignore this directory.

- [worker-configuration.d.ts](src/worker-configuration.d.ts) - This file is owned by Cloudflare. It must not be changed. It is created by "pnpm cf-typegen".

- [security.txt](static/security.txt) - This file should contain the administrator's email. Replace it when you discover it.
- Running lint "pnpm lint" - The expected result is: "All matched files use Prettier code style!"

# Layout and Components

- https://shadcn-svelte.com/docs/components/sidebar
- [All Frontend Designs directory](src/lib/components)

# Security:

SvelteKit offers native protection against leaking sensitive information through server-only modules. Any file placed in the src/lib/server/ folder or with a .server.js extension is never sent to the client.

Environment variables — like API keys and database credentials — can be added to a `.env` file, and they will be made available to your application.

> [!NOTE] You can also use `.env.local` or `.env.[mode]` files — see the [Vite documentation](https://vitejs.dev/guide/env-and-mode.html#env-files) for more information. Make sure you add any files containing sensitive information to your `.gitignore` file!
>
> Environment variables in `process.env` are also available via `$env/static/private`.

In this exercise, we want to allow the user to enter the website if they know the correct passphrase, using an environment variable.

First, in `.env`, add a new environment variable:

```env
/// file: .env
PASSPHRASE=+++"open sesame"+++
```

Open `src/routes/+page.server.js`. Import `PASSPHRASE` from `$env/static/private` and use it inside the [form action](/tutorial/kit/the-form-element):

```js
/// file: src/routes/+page.server.js
import { redirect, fail } from '@sveltejs/kit';
+++import { PASSPHRASE } from '$env/static/private';+++

export function load({ cookies }) {
	if (cookies.get('allowed')) {
		redirect(307, '/welcome');
	}
}

export const actions = {
	default: async ({ request, cookies }) => {
		const data = await request.formData();

		if (data.get('passphrase') === +++PASSPHRASE+++) {
			cookies.set('allowed', 'true', {
				path: '/'
			});

			redirect(303, '/welcome');
		}

		return fail(403, {
			incorrect: true
		});
	}
};
```

The website is now accessible to anyone who knows the correct passphrase.

## Keeping secrets

It's important that sensitive data doesn't accidentally end up being sent to the browser, where it could easily be stolen by hackers and scoundrels.

SvelteKit makes it easy to prevent this from happening. Notice what happens if we try to import `PASSPHRASE` into `src/routes/+page.svelte`:

```svelte
<script>
	+++import { PASSPHRASE } from '$env/static/private';+++
	let { form } = $props();
</script>

/// file: src/routes/+page.svelte
```

An error overlay pops up, telling us that `$env/static/private` cannot be imported into client-side code. It can only be imported into server modules:

- `+page.server.js`
- `+layout.server.js`
- `+server.js`
- any modules ending with `.server.js`
- any modules inside `src/lib/server`

In turn, these modules can only be imported by _other_ server modules.

## Static vs dynamic

The `static` in `$env/static/private` indicates that these values are known at build time, and can be _statically replaced_. This enables useful optimizations:

```js
import { FEATURE_FLAG_X } from '$env/static/private';

if (FEATURE_FLAG_X === 'enabled') {
	// code in here will be removed from the build output
	// if FEATURE_FLAG_X is not enabled
}
```

In some cases you might need to refer to environment variables that are _dynamic_ — in other words, not known until we run the app. We'll cover this case in the next exercise.

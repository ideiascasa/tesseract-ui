<script lang="ts">
	import SidebarIcon from '@lucide/svelte/icons/sidebar';
	import SearchForm from './search-form.svelte';
	import * as Breadcrumb from '$lib/components/ui/breadcrumb';
	import { Button } from '$lib/components/ui/button';
	import { Separator } from '$lib/components/ui/separator';
	import * as Sidebar from '$lib/components/ui/sidebar';
	import type { ComponentProps } from 'svelte';
	import MenuBread from './menu-bread.svelte';
	import NavActions from './nav-actions.svelte';
	import { page } from '$app/stores';
	import { SidebarTrigger } from '$lib/components/ui/sidebar';

	let { ref = $bindable(null), ...restProps }: ComponentProps<typeof Sidebar.Root> = $props();

	const groups = $derived($page.data.groups || []);
	const isMemberOfGroup1 = $derived(
		groups.some(
			(group: { groupId: string; groupName: string | null; isAdmin: boolean }) =>
				group.groupId === '1'
		)
	);
</script>

<header class="bg-background sticky top-0 z-50 flex w-full items-center border-b px-4">
	<div class="h-(--header-height) flex w-full items-center gap-2" {...restProps}>
		<Button class="size-8" variant="ghost" size="icon">
<!--			<SidebarTrigger className="-ml-1" >-->
			<SidebarIcon />
<!--			</SidebarTrigger>-->
		</Button>
		<Separator orientation="vertical" class="mr-2 h-4" />
		<MenuBread />
	</div>
	<SearchForm class="w-full sm:ml-auto sm:w-auto" />
	{#if isMemberOfGroup1}
		<NavActions />
	{/if}
</header>

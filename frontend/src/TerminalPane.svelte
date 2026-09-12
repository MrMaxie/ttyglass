<script lang="ts">
  import { onMount } from 'svelte';

  import type { ColorScheme } from './lib/color-schemes';
  import {
    createTerminal,
    type TerminalController,
    type TerminalMessage,
    type TerminalSize,
  } from './lib/terminal';

  interface Props {
    onReady: (controller: TerminalController | undefined) => void;
    onSize: (size: TerminalSize) => void;
    scheme: ColorScheme;
    send: (message: TerminalMessage) => boolean;
  }

  let { onReady, onSize, scheme, send }: Props = $props();
  let terminalElement: HTMLDivElement;

  onMount(() => {
    const controller = createTerminal(terminalElement, { onSize, scheme, send });
    onReady(controller);

    return () => {
      onReady(undefined);
      controller.dispose();
    };
  });
</script>

<div class="terminal" bind:this={terminalElement}></div>

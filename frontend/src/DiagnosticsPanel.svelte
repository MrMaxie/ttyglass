<script lang="ts">
  import { tick } from 'svelte';

  import { type DiagnosticEntry, formatDiagnostic } from './lib/diagnostics';

  interface Props {
    entries: DiagnosticEntry[];
    onClear: () => void;
  }

  let { entries, onClear }: Props = $props();
  let logOutput: HTMLDivElement;

  $effect(() => {
    entries;
    void tick().then(() => {
      logOutput.scrollTop = logOutput.scrollHeight;
    });
  });
</script>

<section id="diagnostics" class="diagnostics" aria-labelledby="diagnostics-title">
  <header>
    <h2 id="diagnostics-title">Diagnostics</h2>
    <button type="button" class="secondary" disabled={entries.length === 0} onclick={onClear}>Clear</button>
  </header>
  <div class="log-output" bind:this={logOutput} role="log">
    {#if entries.length === 0}
      <p data-empty-diagnostics>No application diagnostics received.</p>
    {:else}
      {#each entries as entry}
        <div class={`log-row level-${entry.level}`}>{formatDiagnostic(entry)}</div>
      {/each}
    {/if}
  </div>
</section>

import { Component, inject } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { toSignal } from '@angular/core/rxjs-interop';
import { map } from 'rxjs';

/**
 * Honest placeholder for planned modules. It explicitly states the module is not
 * built yet rather than faking business functionality.
 */
@Component({
  selector: 'app-placeholder',
  imports: [],
  template: `
    <h1>{{ title() }}</h1>
    <div class="placeholder">
      <p>This module is planned but not implemented yet.</p>
      <p class="muted">
        The foundation (auth, multi-tenancy, API conventions, logging, tests) is in place. This feature will be
        added in a later, dedicated module prompt. See <code>docs/module-roadmap.md</code>.
      </p>
    </div>
  `,
  styles: [
    `
      .placeholder {
        background: #fff;
        border: 1px dashed #c9d3ce;
        border-radius: 8px;
        padding: 1.5rem;
        max-width: 640px;
      }
      .muted { color: #6b7772; }
    `
  ]
})
export class PlaceholderComponent {
  private readonly route = inject(ActivatedRoute);

  protected readonly title = toSignal(
    this.route.paramMap.pipe(
      map((p) => {
        const module = p.get('module') ?? 'module';
        return module
          .split('-')
          .map((s) => s.charAt(0).toUpperCase() + s.slice(1))
          .join(' ');
      })
    ),
    { initialValue: 'Module' }
  );
}

import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

@Component({
  selector: 'app-forbidden',
  imports: [RouterLink],
  template: `
    <div class="forbidden">
      <h1>403 — Forbidden</h1>
      <p>You do not have permission to view this page.</p>
      <a routerLink="/dashboard">Back to dashboard</a>
    </div>
  `,
  styles: [
    `
      .forbidden {
        max-width: 480px;
        margin: 4rem auto;
        text-align: center;
      }
    `
  ]
})
export class ForbiddenComponent {}

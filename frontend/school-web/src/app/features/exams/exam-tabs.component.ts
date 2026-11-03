import { Component } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';

/** Shared tab bar for the Exams & Report Cards section. */
@Component({
  selector: 'app-exam-tabs',
  imports: [RouterLink, RouterLinkActive],
  template: `
    <nav class="exam-tabs">
      <a routerLink="/exams" routerLinkActive="active" [routerLinkActiveOptions]="{ exact: true }">Examination</a>
      <a routerLink="/exams/marks" routerLinkActive="active">Marks Entry</a>
      <a routerLink="/exams/results" routerLinkActive="active">Results</a>
      <a routerLink="/exams/report-cards" routerLinkActive="active">Report Cards</a>
    </nav>
  `,
  styles: [`
    .exam-tabs {
      display: flex;
      flex-wrap: wrap;
      gap: 0.25rem;
      border-bottom: 1px solid #e0e4e2;
      margin-bottom: 1.25rem;
    }
    .exam-tabs a {
      padding: 0.55rem 1rem;
      color: #5a665f;
      text-decoration: none;
      font-size: 0.92rem;
      border-bottom: 2px solid transparent;
    }
    .exam-tabs a:hover { color: #0f5132; }
    .exam-tabs a.active { color: #0f5132; border-bottom-color: #0f5132; font-weight: 600; }
  `]
})
export class ExamTabsComponent {}

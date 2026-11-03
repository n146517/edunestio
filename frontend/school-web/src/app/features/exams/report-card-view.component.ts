import { Component, inject, signal } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { DecimalPipe } from '@angular/common';
import { ExamService } from '../../core/services/exam.service';
import { NotificationService } from '../../core/services/notification.service';
import { ReportCard } from '../../core/models/api.models';

/** Printable individual report card (screen 10). Opened in its own tab. */
@Component({
  selector: 'app-report-card-view',
  imports: [DecimalPipe],
  templateUrl: './report-card-view.component.html',
  styleUrl: './report-card-view.component.scss'
})
export class ReportCardViewComponent {
  private readonly api = inject(ExamService);
  private readonly route = inject(ActivatedRoute);
  private readonly notify = inject(NotificationService);

  protected readonly card = signal<ReportCard | null>(null);
  protected readonly state = signal<'loading' | 'ready' | 'error'>('loading');

  constructor() {
    const examId = Number(this.route.snapshot.paramMap.get('examId'));
    const studentId = Number(this.route.snapshot.paramMap.get('studentId'));
    this.api.reportCard(examId, studentId).subscribe({
      next: (c) => { if (c) { this.card.set(c); this.state.set('ready'); } else { this.state.set('error'); } },
      error: () => this.state.set('error')
    });
  }

  protected print(): void {
    window.print();
  }

  protected marksText(s: { is_absent: boolean; marks: number | null }): string {
    if (s.is_absent) return 'AB';
    return s.marks !== null && s.marks !== undefined ? String(s.marks) : '—';
  }
}

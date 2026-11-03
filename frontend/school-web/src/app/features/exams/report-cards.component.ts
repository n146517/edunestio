import { Component, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { DecimalPipe } from '@angular/common';
import { ExamService } from '../../core/services/exam.service';
import { AcademicService } from '../../core/services/academic.service';
import { AcademicYearStore } from '../../core/state/academic-year.store';
import { NotificationService } from '../../core/services/notification.service';
import { Exam, ReportCardList, Section } from '../../core/models/api.models';
import { ExamTabsComponent } from './exam-tabs.component';

/** Class-wise report cards (screen 9). */
@Component({
  selector: 'app-report-cards',
  imports: [FormsModule, DecimalPipe, ExamTabsComponent],
  templateUrl: './report-cards.component.html',
  styleUrl: './report-cards.component.scss'
})
export class ReportCardsComponent {
  private readonly api = inject(ExamService);
  private readonly academic = inject(AcademicService);
  private readonly notify = inject(NotificationService);
  private readonly router = inject(Router);
  private readonly yearStore = inject(AcademicYearStore);

  protected readonly exams = signal<Exam[]>([]);
  protected readonly sections = signal<Section[]>([]);
  protected readonly list = signal<ReportCardList | null>(null);
  protected readonly loading = signal(false);

  protected examId = 0;
  protected classId = 0;
  protected sectionId = 0;

  constructor() {
    this.yearStore.load();
    effect(() => {
      const year = this.yearStore.filterId();
      this.api.list({ academicYearId: year }).subscribe((e) => this.exams.set(e));
    });
  }

  protected classesForExam(): { class_id: number; name: string }[] {
    return this.exams().find((e) => e.exam_id === this.examId)?.classes ?? [];
  }

  protected onExamChange(): void {
    this.classId = 0; this.sectionId = 0; this.sections.set([]); this.list.set(null);
  }
  protected onClassChange(): void {
    this.sectionId = 0; this.list.set(null); this.sections.set([]);
    if (this.classId) this.academic.listSections(this.classId).subscribe((s) => this.sections.set(s));
  }

  protected canGenerate(): boolean { return !!(this.examId && this.classId); }

  protected generate(): void {
    if (!this.canGenerate()) { this.notify.info('Select an exam and class.'); return; }
    this.loading.set(true);
    this.api.reportCardList(this.examId, this.classId, this.sectionId || undefined).subscribe({
      next: (l) => { this.loading.set(false); this.list.set(l); },
      error: () => { this.loading.set(false); this.notify.error('Could not load report cards.'); }
    });
  }

  /** Open the printable individual card in a new tab. */
  protected viewCard(studentId: number): void {
    const url = this.router.serializeUrl(
      this.router.createUrlTree(['/exams', this.examId, 'report-card', studentId]));
    window.open(url, '_blank');
  }

  protected resultClass(r: string): string {
    if (r === 'Pass') return 'res res--pass';
    if (r === 'Fail') return 'res res--fail';
    return 'res';
  }
}

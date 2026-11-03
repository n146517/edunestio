import { Component, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DecimalPipe } from '@angular/common';
import { ExamService } from '../../core/services/exam.service';
import { AcademicService } from '../../core/services/academic.service';
import { AuthStore } from '../../core/auth/auth.store';
import { AcademicYearStore } from '../../core/state/academic-year.store';
import { NotificationService } from '../../core/services/notification.service';
import { Exam, ResultPreview, Section } from '../../core/models/api.models';
import { ExamTabsComponent } from './exam-tabs.component';

/** Result preview + publish (screens 7-8). */
@Component({
  selector: 'app-results',
  imports: [FormsModule, DecimalPipe, ExamTabsComponent],
  templateUrl: './results.component.html',
  styleUrl: './results.component.scss'
})
export class ResultsComponent {
  private readonly api = inject(ExamService);
  private readonly academic = inject(AcademicService);
  private readonly notify = inject(NotificationService);
  protected readonly store = inject(AuthStore);
  private readonly yearStore = inject(AcademicYearStore);

  protected readonly exams = signal<Exam[]>([]);
  protected readonly sections = signal<Section[]>([]);
  protected readonly preview = signal<ResultPreview | null>(null);
  protected readonly loading = signal(false);

  protected examId = 0;
  protected classId = 0;
  protected sectionId = 0;

  // Publish dialog
  protected readonly publishOpen = signal(false);
  protected publishVerified = false;
  protected forceOverride = false;
  protected publishing = signal(false);

  protected readonly canPublish = this.store.hasPermission('exam.publish');

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
  protected selectedExam(): Exam | undefined {
    return this.exams().find((e) => e.exam_id === this.examId);
  }

  /** Dropdown label that distinguishes exams across academic years. */
  protected examLabel(e: Exam): string {
    const year = e.academic_year_name ?? (e.start_date ? new Date(e.start_date).getFullYear().toString() : null);
    return year ? `${e.name} — ${year}` : e.name;
  }

  /** Whether the currently-selected exam is already published. */
  protected isPublished(): boolean {
    return !!this.selectedExam()?.is_published;
  }

  protected onExamChange(): void {
    this.classId = 0; this.sectionId = 0; this.sections.set([]); this.preview.set(null);
  }

  protected onClassChange(): void {
    this.sectionId = 0; this.preview.set(null);
    this.sections.set([]);
    if (this.classId) this.academic.listSections(this.classId).subscribe((s) => this.sections.set(s));
  }

  protected canCalc(): boolean { return !!(this.examId && this.classId); }

  protected calculate(): void {
    if (!this.canCalc()) { this.notify.info('Select an exam and class.'); return; }
    this.loading.set(true);
    this.api.resultPreview(this.examId, this.classId, this.sectionId || undefined).subscribe({
      next: (p) => { this.loading.set(false); this.preview.set(p); },
      error: () => { this.loading.set(false); this.notify.error('Could not calculate results.'); }
    });
  }

  protected checkMissing(): void {
    // Same call; surface which subjects are pending in a toast.
    this.api.resultPreview(this.examId, this.classId, this.sectionId || undefined).subscribe((p) => {
      this.preview.set(p);
      if (!p) return;
      if (p.missing === 0) {
        this.notify.success('All marks are complete.');
        return;
      }
      // Collect the distinct subjects that are still unmarked for anyone.
      const subjects = new Set<string>();
      for (const r of p.items) {
        if (r.status === 'Missing' && r.missing_subjects) {
          r.missing_subjects.split(',').forEach((s) => subjects.add(s.trim()));
        }
      }
      const subjList = subjects.size ? ` Pending subject(s): ${Array.from(subjects).join(', ')}.` : '';
      this.notify.info(`${p.missing} student(s) still have missing marks.${subjList}`);
    });
  }

  protected openPublish(): void {
    const p = this.preview();
    if (!p) { this.notify.info('Calculate results first.'); return; }
    this.publishVerified = false;
    this.forceOverride = false;
    this.publishOpen.set(true);
  }

  protected closePublish(): void {
    this.publishOpen.set(false);
  }

  protected confirmPublish(): void {
    const exam = this.selectedExam();
    if (!exam || !this.publishVerified) return;
    const wasPublished = exam.is_published;
    this.publishing.set(true);
    this.api.publish(exam.exam_id, true, this.forceOverride).subscribe({
      next: (res) => {
        this.publishing.set(false);
        if (res.isSuccess) {
          // Report cards are computed live, so re-publishing simply pushes the
          // latest (edited) marks to the already-visible report cards.
          this.notify.success(wasPublished ? 'Results re-published with the latest marks.' : 'Results published.');
          this.closePublish();
          this.calculate();
          this.exams.update((list) => list.map((e) => e.exam_id === exam.exam_id ? { ...e, is_published: true, status: 'Published' } : e));
        } else {
          this.notify.error(res.resultCodeDescription ?? 'Publish failed.');
        }
      },
      error: () => this.publishing.set(false)
    });
  }

  /** Unpublish: hide results/report cards again (e.g. to correct a mistake). */
  protected unpublish(): void {
    const exam = this.selectedExam();
    if (!exam) return;
    if (!confirm(`Unpublish "${exam.name}"? Report cards will be hidden until you publish again.`)) return;
    this.publishing.set(true);
    this.api.publish(exam.exam_id, false, false).subscribe({
      next: (res) => {
        this.publishing.set(false);
        if (res.isSuccess) {
          this.notify.success('Results unpublished.');
          this.calculate();
          this.exams.update((list) => list.map((e) => e.exam_id === exam.exam_id ? { ...e, is_published: false, status: 'Completed' } : e));
        } else {
          this.notify.error(res.resultCodeDescription ?? 'Unpublish failed.');
        }
      },
      error: () => this.publishing.set(false)
    });
  }

  protected statusClass(s: string): string {
    return s === 'Ready' ? 'badge badge--ready' : 'badge badge--missing';
  }
  protected resultClass(r: string): string {
    if (r === 'Pass') return 'res res--pass';
    if (r === 'Fail') return 'res res--fail';
    return 'res';
  }
}

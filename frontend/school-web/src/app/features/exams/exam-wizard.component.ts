import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { ExamService } from '../../core/services/exam.service';
import { AcademicService } from '../../core/services/academic.service';
import { NotificationService } from '../../core/services/notification.service';
import {
  AcademicYear,
  ExamScheduleRow,
  ExamSubjectRow,
  SchoolClass,
  Subject
} from '../../core/models/api.models';

type Step = 1 | 2 | 3 | 4;

/** Create / edit exam wizard: Details -> Classes & Subjects -> Schedule -> Settings. */
@Component({
  selector: 'app-exam-wizard',
  imports: [FormsModule, RouterLink],
  templateUrl: './exam-wizard.component.html',
  styleUrl: './exam-wizard.component.scss'
})
export class ExamWizardComponent {
  private readonly api = inject(ExamService);
  private readonly academic = inject(AcademicService);
  private readonly notify = inject(NotificationService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  protected readonly step = signal<Step>(1);
  protected readonly examId = signal<number | null>(null);
  protected readonly saving = signal(false);

  protected readonly classes = signal<SchoolClass[]>([]);
  protected readonly years = signal<AcademicYear[]>([]);
  protected readonly subjects = signal<Subject[]>([]);

  protected readonly examTypes = ['Term Exam', 'Unit Test', 'Mid Term', 'Final Exam', 'Practical', 'Annual Examination'];

  // Step 1 — details
  protected details = {
    Name: '',
    ExamType: '',
    AcademicYearId: 0,
    StartDate: '',
    EndDate: '',
    Description: ''
  };
  protected selectedClassIds = signal<number[]>([]);

  // Step 2 — per-class subjects. Keyed by class id.
  protected readonly activeClass = signal<number>(0);
  protected readonly classSubjects = signal<Record<number, ExamSubjectRow[]>>({});

  // Step 3 — schedule rows
  protected readonly scheduleRows = signal<ExamScheduleRow[]>([]);
  protected readonly subjectTypes = ['Theory', 'Practical'];

  constructor() {
    this.academic.listClasses().subscribe((c) => this.classes.set(c));
    this.academic.listYears().subscribe((y) => this.years.set(y));
    this.academic.listSubjects().subscribe((s) => this.subjects.set(s));

    const id = this.route.snapshot.paramMap.get('id');
    if (id) {
      this.examId.set(Number(id));
      this.loadExam(Number(id));
    }
  }

  protected get isEdit(): boolean { return this.examId() !== null; }

  private loadExam(id: number): void {
    this.api.get(id).subscribe((e) => {
      if (!e) { this.notify.error('Exam not found.'); void this.router.navigate(['/exams']); return; }
      this.details = {
        Name: e.name,
        ExamType: e.exam_type ?? '',
        AcademicYearId: e.academic_year_id ?? 0,
        StartDate: e.start_date ? e.start_date.substring(0, 10) : '',
        EndDate: e.end_date ? e.end_date.substring(0, 10) : '',
        Description: e.description ?? ''
      };
      this.selectedClassIds.set([...e.class_ids]);
    });
  }

  // ---- Step 1 ----
  protected isClassSelected(id: number): boolean {
    return this.selectedClassIds().includes(id);
  }
  protected toggleClass(id: number): void {
    const cur = this.selectedClassIds();
    this.selectedClassIds.set(cur.includes(id) ? cur.filter((x) => x !== id) : [...cur, id]);
  }

  protected saveDetailsAndNext(): void {
    if (!this.details.Name.trim()) { this.notify.info('Exam name is required.'); return; }
    if (!this.selectedClassIds().length) { this.notify.info('Select at least one class.'); return; }
    this.saving.set(true);
    this.api.save({
      ExamId: this.examId(),
      Name: this.details.Name.trim(),
      ExamType: this.details.ExamType || null,
      AcademicYearId: this.details.AcademicYearId || null,
      StartDate: this.details.StartDate || null,
      EndDate: this.details.EndDate || null,
      Description: this.details.Description || null,
      ClassIds: this.selectedClassIds()
    }).subscribe({
      next: (r) => {
        this.saving.set(false);
        if (!r.isSuccess) { this.notify.error(r.resultCodeDescription ?? 'Save failed.'); return; }
        const newId = this.examId() ?? (r.data as { exam_id?: number } | null)?.exam_id ?? null;
        this.examId.set(newId);
        this.notify.success('Exam saved.');
        this.goToSubjects();
      },
      error: () => this.saving.set(false)
    });
  }

  // ---- Step 2 ----
  private goToSubjects(): void {
    const first = this.selectedClassIds()[0] ?? 0;
    this.activeClass.set(first);
    this.step.set(2);
    this.loadClassSubjects(first);
  }

  protected selectClassTab(classId: number): void {
    this.activeClass.set(classId);
    if (!(classId in this.classSubjects())) this.loadClassSubjects(classId);
  }

  private loadClassSubjects(classId: number): void {
    const id = this.examId();
    if (!id || !classId) return;
    this.api.classSubjects(id, classId).subscribe((rows) => {
      this.classSubjects.update((m) => ({ ...m, [classId]: rows }));
    });
  }

  protected rowsFor(classId: number): ExamSubjectRow[] {
    return this.classSubjects()[classId] ?? [];
  }

  protected className(classId: number): string {
    return this.classes().find((c) => c.class_id === classId)?.name ?? `Class ${classId}`;
  }

  protected addSubjectRow(): void {
    const classId = this.activeClass();
    const rows = [...this.rowsFor(classId)];
    rows.push({ subject_id: 0, max_marks: 100, pass_marks: 33, subject_type: 'Theory' });
    this.classSubjects.update((m) => ({ ...m, [classId]: rows }));
  }

  protected removeSubjectRow(index: number): void {
    const classId = this.activeClass();
    const rows = this.rowsFor(classId).filter((_, i) => i !== index);
    this.classSubjects.update((m) => ({ ...m, [classId]: rows }));
  }

  protected saveCurrentClassSubjects(then?: () => void): void {
    const id = this.examId();
    const classId = this.activeClass();
    if (!id || !classId) return;
    const rows = this.rowsFor(classId).filter((r) => r.subject_id);
    this.saving.set(true);
    this.api.saveClassSubjects({
      ExamId: id,
      ClassId: classId,
      Subjects: rows.map((r) => ({
        ExamSubjectId: r.exam_subject_id ?? null,
        SubjectId: r.subject_id,
        MaxMarks: r.max_marks,
        PassMarks: r.pass_marks,
        SubjectType: r.subject_type
      }))
    }).subscribe({
      next: (res) => {
        this.saving.set(false);
        if (!res.isSuccess) { this.notify.error(res.resultCodeDescription ?? 'Save failed.'); return; }
        this.notify.success(`Saved ${this.className(classId)} subjects.`);
        this.loadClassSubjects(classId);
        then?.();
      },
      error: () => this.saving.set(false)
    });
  }

  protected subjectsAndNext(): void {
    // Save the current class, then move to schedule.
    this.saveCurrentClassSubjects(() => this.goToSchedule());
  }

  // ---- Step 3 ----
  private goToSchedule(): void {
    const id = this.examId();
    if (!id) return;
    this.step.set(3);
    this.api.schedule(id).subscribe((rows) => this.scheduleRows.set(rows));
  }

  protected saveScheduleAndNext(): void {
    const id = this.examId();
    if (!id) return;
    this.saving.set(true);
    this.api.saveSchedule({
      ExamId: id,
      Items: this.scheduleRows().map((r) => ({
        ExamSubjectId: r.exam_subject_id,
        ExamDate: r.exam_date || null,
        StartTime: r.start_time || null,
        EndTime: r.end_time || null,
        Room: r.room || null
      }))
    }).subscribe({
      next: (res) => {
        this.saving.set(false);
        if (!res.isSuccess) { this.notify.error(res.resultCodeDescription ?? 'Save failed.'); return; }
        this.notify.success('Schedule saved.');
        this.step.set(4);
      },
      error: () => this.saving.set(false)
    });
  }

  protected finish(): void {
    this.notify.success('Exam setup complete.');
    void this.router.navigate(['/exams']);
  }

  protected back(): void {
    const s = this.step();
    if (s > 1) this.step.set((s - 1) as Step);
  }

  protected cancel(): void {
    void this.router.navigate(['/exams']);
  }
}

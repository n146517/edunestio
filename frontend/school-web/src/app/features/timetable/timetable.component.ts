import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TimetableService } from '../../core/services/timetable.service';
import { AcademicService } from '../../core/services/academic.service';
import { AuthStore } from '../../core/auth/auth.store';
import { NotificationService } from '../../core/services/notification.service';
import { SchoolClass, Section, Subject, Teacher, TimetableSlot } from '../../core/models/api.models';

/** Weekly timetable builder: pick class/section, click a cell to set subject + teacher. */
@Component({
  selector: 'app-timetable',
  imports: [FormsModule],
  templateUrl: './timetable.component.html',
  styleUrl: './timetable.component.scss'
})
export class TimetableComponent {
  private readonly api = inject(TimetableService);
  private readonly academic = inject(AcademicService);
  private readonly notify = inject(NotificationService);
  protected readonly store = inject(AuthStore);

  protected readonly classes = signal<SchoolClass[]>([]);
  protected readonly sections = signal<Section[]>([]);
  protected readonly subjects = signal<Subject[]>([]);
  protected readonly teachers = signal<Teacher[]>([]);
  protected readonly slots = signal<TimetableSlot[]>([]);
  protected readonly loading = signal(false);

  protected classId = 0;
  protected sectionId = 0;

  protected readonly canManage = this.store.hasPermission('timetable.manage');

  protected readonly days = [
    { n: 1, label: 'Monday' }, { n: 2, label: 'Tuesday' }, { n: 3, label: 'Wednesday' },
    { n: 4, label: 'Thursday' }, { n: 5, label: 'Friday' }, { n: 6, label: 'Saturday' }
  ];
  protected readonly periods = [1, 2, 3, 4, 5, 6, 7, 8];

  // Slot editor dialog state.
  protected readonly editorOpen = signal(false);
  protected editDay = 0;
  protected editPeriod = 0;
  protected editSlotId: number | null = null;
  protected formSubjectId = 0;
  protected formTeacherId = 0;
  protected formStart = '';
  protected formEnd = '';
  protected formRoom = '';
  protected readonly busy = signal(false);

  constructor() {
    this.academic.listClasses().subscribe((c) => this.classes.set(c));
    this.academic.listSubjects().subscribe((s) => this.subjects.set(s.filter((x) => x.is_active)));
    if (this.canManage) this.api.teachers().subscribe((t) => this.teachers.set(t));
  }

  protected onClassChange(): void {
    this.sectionId = 0;
    this.sections.set([]);
    this.slots.set([]);
    if (this.classId) {
      this.academic.listSections(this.classId).subscribe((s) => this.sections.set(s));
      this.loadGrid();
    }
  }

  protected onSectionChange(): void { this.loadGrid(); }

  protected loadGrid(): void {
    if (!this.classId) return;
    this.loading.set(true);
    this.api.list(this.classId, this.sectionId || undefined).subscribe({
      next: (s) => { this.slots.set(s); this.loading.set(false); },
      error: () => this.loading.set(false)
    });
  }

  /** Find the slot at a given day+period (or undefined). */
  protected slotAt(day: number, period: number): TimetableSlot | undefined {
    return this.slots().find((s) => s.day_of_week === day && s.period_no === period);
  }

  protected openEditor(day: number, period: number): void {
    if (!this.canManage || !this.classId) return;
    const existing = this.slotAt(day, period);
    this.editDay = day;
    this.editPeriod = period;
    this.editSlotId = existing?.slot_id ?? null;
    this.formSubjectId = existing?.subject_id ?? 0;
    this.formTeacherId = existing?.teacher_id ?? 0;
    this.formStart = existing?.start_time ? existing.start_time.substring(0, 5) : '';
    this.formEnd = existing?.end_time ? existing.end_time.substring(0, 5) : '';
    this.formRoom = existing?.room ?? '';
    this.editorOpen.set(true);
  }

  protected closeEditor(): void { this.editorOpen.set(false); }

  protected saveSlot(): void {
    if (this.busy()) return;
    this.busy.set(true);
    this.api.save({
      SlotId: this.editSlotId,
      ClassId: this.classId,
      SectionId: this.sectionId || null,
      DayOfWeek: this.editDay,
      PeriodNo: this.editPeriod,
      StartTime: this.formStart || null,
      EndTime: this.formEnd || null,
      SubjectId: this.formSubjectId || null,
      TeacherId: this.formTeacherId || null,
      Room: this.formRoom || null
    }).subscribe({
      next: (res) => {
        this.busy.set(false);
        if (res.isSuccess) { this.notify.success('Slot saved.'); this.closeEditor(); this.loadGrid(); }
        else this.notify.error(res.resultCodeDescription ?? 'Could not save.');
      },
      error: () => this.busy.set(false)
    });
  }

  protected deleteSlot(): void {
    if (!this.editSlotId || this.busy()) return;
    if (!confirm('Clear this period?')) return;
    this.busy.set(true);
    this.api.delete(this.editSlotId).subscribe({
      next: (res) => {
        this.busy.set(false);
        if (res.isSuccess) { this.notify.success('Cleared.'); this.closeEditor(); this.loadGrid(); }
        else this.notify.error(res.resultCodeDescription ?? 'Could not clear.');
      },
      error: () => this.busy.set(false)
    });
  }

  protected subjectName(id: number): string {
    return this.subjects().find((s) => s.subject_id === id)?.name ?? '';
  }
}

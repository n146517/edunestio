import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { AcademicService } from '../../core/services/academic.service';
import { AuthStore } from '../../core/auth/auth.store';
import { NotificationService } from '../../core/services/notification.service';
import { AcademicYear, SchoolClass, Section, Subject } from '../../core/models/api.models';

type Tab = 'years' | 'classes' | 'sections' | 'subjects';

@Component({
  selector: 'app-academic-setup',
  imports: [ReactiveFormsModule],
  templateUrl: './academic-setup.component.html',
  styleUrl: './academic-setup.component.scss'
})
export class AcademicSetupComponent {
  private readonly api = inject(AcademicService);
  private readonly fb = inject(FormBuilder);
  private readonly notify = inject(NotificationService);
  protected readonly store = inject(AuthStore);

  protected readonly tab = signal<Tab>('classes');
  protected readonly loading = signal(false);
  protected readonly saving = signal(false);

  protected readonly years = signal<AcademicYear[]>([]);
  protected readonly classes = signal<SchoolClass[]>([]);
  protected readonly sections = signal<Section[]>([]);
  protected readonly subjects = signal<Subject[]>([]);

  protected readonly canManage = this.store.hasPermission('academic.manage');

  protected readonly yearForm = this.fb.nonNullable.group({
    Name: ['', Validators.required],
    StartDate: ['', Validators.required],
    EndDate: ['', Validators.required],
    IsCurrent: [false]
  });
  protected readonly classForm = this.fb.nonNullable.group({
    Name: ['', Validators.required],
    Ordinal: [0]
  });
  protected readonly sectionForm = this.fb.nonNullable.group({
    ClassId: [0, Validators.required],
    Name: ['', Validators.required]
  });
  protected readonly subjectForm = this.fb.nonNullable.group({
    Name: ['', Validators.required],
    Code: ['', Validators.required],
    IsActive: [true]
  });

  constructor() {
    this.loadAll();
  }

  protected setTab(t: Tab): void {
    this.tab.set(t);
  }

  protected loadAll(): void {
    this.loading.set(true);
    this.api.listClasses().subscribe((c) => { this.classes.set(c); this.loading.set(false); });
    this.api.listYears().subscribe((y) => this.years.set(y));
    this.api.listSections().subscribe((s) => this.sections.set(s));
    this.api.listSubjects().subscribe((s) => this.subjects.set(s));
  }

  protected addYear(): void {
    if (this.yearForm.invalid || this.saving()) { this.yearForm.markAllAsTouched(); return; }
    this.saving.set(true);
    this.api.saveYear(this.yearForm.getRawValue()).subscribe({
      next: (r) => { this.after(r.isSuccess, 'Academic year saved.', r.resultCodeDescription); this.yearForm.reset({ IsCurrent: false, Name: '', StartDate: '', EndDate: '' }); this.api.listYears().subscribe((y) => this.years.set(y)); },
      error: () => this.saving.set(false)
    });
  }

  protected addClass(): void {
    if (this.classForm.invalid || this.saving()) { this.classForm.markAllAsTouched(); return; }
    this.saving.set(true);
    this.api.saveClass(this.classForm.getRawValue()).subscribe({
      next: (r) => { this.after(r.isSuccess, 'Class saved.', r.resultCodeDescription); this.classForm.reset({ Name: '', Ordinal: 0 }); this.api.listClasses().subscribe((c) => this.classes.set(c)); },
      error: () => this.saving.set(false)
    });
  }

  protected addSection(): void {
    if (this.sectionForm.invalid || this.saving()) { this.sectionForm.markAllAsTouched(); return; }
    this.saving.set(true);
    this.api.saveSection(this.sectionForm.getRawValue()).subscribe({
      next: (r) => { this.after(r.isSuccess, 'Section saved.', r.resultCodeDescription); this.sectionForm.reset({ ClassId: 0, Name: '' }); this.api.listSections().subscribe((s) => this.sections.set(s)); },
      error: () => this.saving.set(false)
    });
  }

  protected addSubject(): void {
    if (this.subjectForm.invalid || this.saving()) { this.subjectForm.markAllAsTouched(); return; }
    this.saving.set(true);
    this.api.saveSubject(this.subjectForm.getRawValue()).subscribe({
      next: (r) => { this.after(r.isSuccess, 'Subject saved.', r.resultCodeDescription); this.subjectForm.reset({ Name: '', Code: '', IsActive: true }); this.api.listSubjects().subscribe((s) => this.subjects.set(s)); },
      error: () => this.saving.set(false)
    });
  }

  private after(ok: boolean, okMsg: string, failMsg: string | null): void {
    this.saving.set(false);
    if (ok) this.notify.success(okMsg);
    else this.notify.error(failMsg ?? 'Save failed.');
  }
}

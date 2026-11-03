import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { AdmissionService } from '../../core/services/admission.service';
import { AcademicService } from '../../core/services/academic.service';
import { AuthStore } from '../../core/auth/auth.store';
import { NotificationService } from '../../core/services/notification.service';
import { Enquiry, SchoolClass } from '../../core/models/api.models';

type LoadState = 'loading' | 'success' | 'error';

@Component({
  selector: 'app-admissions',
  imports: [ReactiveFormsModule],
  templateUrl: './admissions.component.html',
  styleUrl: './admissions.component.scss'
})
export class AdmissionsComponent {
  private readonly api = inject(AdmissionService);
  private readonly academic = inject(AcademicService);
  private readonly fb = inject(FormBuilder);
  private readonly notify = inject(NotificationService);
  protected readonly store = inject(AuthStore);

  protected readonly state = signal<LoadState>('loading');
  protected readonly items = signal<Enquiry[]>([]);
  protected readonly classes = signal<SchoolClass[]>([]);
  protected readonly stageFilter = signal('');
  protected readonly showForm = signal(false);
  protected readonly saving = signal(false);

  protected readonly canManage = this.store.hasPermission('admission.manage');
  protected readonly canConvert = this.store.hasPermission('admission.convert');
  protected readonly stages = ['New', 'Contacted', 'Application', 'Accepted', 'Admitted', 'Rejected', 'Lost'];

  protected readonly form = this.fb.nonNullable.group({
    ApplicantName: ['', Validators.required],
    GuardianName: [''],
    Phone: [''],
    Email: [''],
    Source: ['Walk-in'],
    DesiredClassId: [0]
  });

  constructor() {
    this.load();
    this.academic.listClasses().subscribe((c) => this.classes.set(c));
  }

  protected load(): void {
    this.state.set('loading');
    this.api.listEnquiries({ stage: this.stageFilter() || undefined, pageSize: 100 }).subscribe({
      next: (p) => { this.items.set(p?.items ?? []); this.state.set('success'); },
      error: () => this.state.set('error')
    });
  }

  protected filterStage(v: string): void { this.stageFilter.set(v); this.load(); }
  protected toggleForm(): void { this.showForm.update((v) => !v); }

  protected create(): void {
    if (this.form.invalid || this.saving()) { this.form.markAllAsTouched(); return; }
    this.saving.set(true);
    const v = this.form.getRawValue();
    this.api.saveEnquiry({
      ApplicantName: v.ApplicantName,
      GuardianName: v.GuardianName || null,
      Phone: v.Phone || null,
      Email: v.Email || null,
      Source: v.Source || null,
      DesiredClassId: v.DesiredClassId || null
    }).subscribe({
      next: (r) => {
        this.saving.set(false);
        if (r.isSuccess) { this.notify.success('Enquiry created.'); this.form.reset({ Source: 'Walk-in', DesiredClassId: 0, ApplicantName: '', GuardianName: '', Phone: '', Email: '' }); this.showForm.set(false); this.load(); }
        else this.notify.error(r.resultCodeDescription ?? 'Failed.');
      },
      error: () => this.saving.set(false)
    });
  }

  protected convert(e: Enquiry): void {
    if (!confirm(`Convert "${e.applicant_name}" (${e.enquiry_number}) into a student?`)) return;
    this.api.convert(e.enquiry_id).subscribe({
      next: (r) => {
        if (r.isSuccess) { this.notify.success('Converted to student.'); this.load(); }
        else this.notify.error(r.resultCodeDescription ?? 'Conversion failed.');
      }
    });
  }

  protected advance(e: Enquiry, stage: string): void {
    this.api.addFollowup(e.enquiry_id, { Note: `Stage changed to ${stage}`, Stage: stage }).subscribe({
      next: (r) => { if (r.isSuccess) { this.notify.success('Updated.'); this.load(); } }
    });
  }
}

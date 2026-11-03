import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { StudentService } from '../../core/services/student.service';
import { AcademicService } from '../../core/services/academic.service';
import { NotificationService } from '../../core/services/notification.service';
import {
  AcademicYear,
  SchoolClass,
  Section,
  StudentDetail,
  StudentUpsert
} from '../../core/models/api.models';

/** Create / edit a student. Sectioned form; section options depend on class. */
@Component({
  selector: 'app-student-form',
  imports: [ReactiveFormsModule, RouterLink],
  templateUrl: './student-form.component.html',
  styleUrl: './student-form.component.scss'
})
export class StudentFormComponent {
  private readonly fb = inject(FormBuilder);
  private readonly api = inject(StudentService);
  private readonly academic = inject(AcademicService);
  private readonly notify = inject(NotificationService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  protected readonly classes = signal<SchoolClass[]>([]);
  protected readonly sections = signal<Section[]>([]);
  protected readonly years = signal<AcademicYear[]>([]);

  protected readonly studentId = signal<number | null>(null);
  protected readonly admissionNumber = signal<string | null>(null);
  protected readonly saving = signal(false);
  protected readonly loading = signal(false);
  protected get isEdit(): boolean { return this.studentId() !== null; }

  protected readonly genders = ['Male', 'Female', 'Other'];
  protected readonly bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  protected readonly form = this.fb.nonNullable.group({
    // Personal
    FirstName: ['', [Validators.required, Validators.maxLength(100)]],
    MiddleName: [''],
    LastName: ['', [Validators.required, Validators.maxLength(100)]],
    Gender: [''],
    DateOfBirth: [''],
    Nationality: [''],
    BloodGroup: [''],
    PhotoUrl: [''],
    // Academic
    ClassId: [0],
    SectionId: [0],
    AcademicYearId: [0],
    RollNumber: [''],
    AdmissionDate: [''],
    // Guardian
    GuardianName: [''],
    GuardianRelation: [''],
    GuardianPhone: ['', [Validators.pattern(/^[+0-9().\-\s]{6,20}$/)]],
    GuardianAltPhone: ['', [Validators.pattern(/^[+0-9().\-\s]{6,20}$/)]],
    GuardianEmail: ['', [Validators.email]],
    // Contact
    Email: ['', [Validators.email]],
    Phone: ['', [Validators.pattern(/^[+0-9().\-\s]{6,20}$/)]],
    // Address
    AddressLine1: [''],
    AddressLine2: [''],
    City: [''],
    State: [''],
    PostalCode: [''],
    Country: ['']
  });

  constructor() {
    this.academic.listClasses().subscribe((c) => this.classes.set(c));
    this.academic.listYears().subscribe((y) => this.years.set(y));

    const idParam = this.route.snapshot.paramMap.get('id');
    if (idParam) {
      this.studentId.set(Number(idParam));
      this.loadStudent(Number(idParam));
    }
  }

  private loadStudent(id: number): void {
    this.loading.set(true);
    this.api.get(id).subscribe({
      next: (s) => {
        this.loading.set(false);
        if (!s) {
          this.notify.error('Student not found.');
          void this.router.navigate(['/students']);
          return;
        }
        this.populate(s);
      },
      error: () => {
        this.loading.set(false);
        this.notify.error('Could not load the student.');
        void this.router.navigate(['/students']);
      }
    });
  }

  private populate(s: StudentDetail): void {
    this.admissionNumber.set(s.admission_number);
    if (s.class_id) {
      this.academic.listSections(s.class_id).subscribe((sec) => this.sections.set(sec));
    }
    this.form.patchValue({
      FirstName: s.first_name,
      MiddleName: s.middle_name ?? '',
      LastName: s.last_name,
      Gender: s.gender ?? '',
      DateOfBirth: s.date_of_birth ? s.date_of_birth.substring(0, 10) : '',
      Nationality: s.nationality ?? '',
      BloodGroup: s.blood_group ?? '',
      PhotoUrl: s.photo_url ?? '',
      ClassId: s.class_id ?? 0,
      SectionId: s.section_id ?? 0,
      AcademicYearId: s.academic_year_id ?? 0,
      RollNumber: s.roll_number ?? '',
      AdmissionDate: s.admission_date ? s.admission_date.substring(0, 10) : '',
      GuardianName: s.guardian_name ?? '',
      GuardianRelation: s.guardian_relation ?? '',
      GuardianPhone: s.guardian_phone ?? '',
      GuardianAltPhone: s.guardian_alt_phone ?? '',
      GuardianEmail: s.guardian_email ?? '',
      Email: s.email ?? '',
      Phone: s.phone ?? '',
      AddressLine1: s.address_line1 ?? '',
      AddressLine2: s.address_line2 ?? '',
      City: s.city ?? '',
      State: s.state ?? '',
      PostalCode: s.postal_code ?? '',
      Country: s.country ?? ''
    });
  }

  protected onClassChange(): void {
    const classId = this.form.controls.ClassId.value;
    this.form.controls.SectionId.setValue(0);
    this.sections.set([]);
    if (classId) {
      this.academic.listSections(classId).subscribe((s) => this.sections.set(s));
    }
  }

  protected invalid(name: keyof typeof this.form.controls): boolean {
    const c = this.form.controls[name];
    return c.invalid && (c.touched || c.dirty);
  }

  protected save(): void {
    if (this.form.invalid || this.saving()) {
      this.form.markAllAsTouched();
      this.notify.info('Please fix the highlighted fields.');
      return;
    }
    const v = this.form.getRawValue();
    const body: StudentUpsert = {
      FirstName: v.FirstName.trim(),
      MiddleName: v.MiddleName || null,
      LastName: v.LastName.trim(),
      Gender: v.Gender || null,
      DateOfBirth: v.DateOfBirth || null,
      Nationality: v.Nationality || null,
      BloodGroup: v.BloodGroup || null,
      PhotoUrl: v.PhotoUrl || null,
      ClassId: v.ClassId || null,
      SectionId: v.SectionId || null,
      AcademicYearId: v.AcademicYearId || null,
      RollNumber: v.RollNumber || null,
      AdmissionDate: v.AdmissionDate || null,
      GuardianName: v.GuardianName || null,
      GuardianRelation: v.GuardianRelation || null,
      GuardianPhone: v.GuardianPhone || null,
      GuardianAltPhone: v.GuardianAltPhone || null,
      GuardianEmail: v.GuardianEmail || null,
      Email: v.Email || null,
      Phone: v.Phone || null,
      AddressLine1: v.AddressLine1 || null,
      AddressLine2: v.AddressLine2 || null,
      City: v.City || null,
      State: v.State || null,
      PostalCode: v.PostalCode || null,
      Country: v.Country || null
    };

    this.saving.set(true);
    const id = this.studentId();
    const req$ = id ? this.api.update(id, body) : this.api.create(body);
    req$.subscribe({
      next: (res) => {
        this.saving.set(false);
        if (res.isSuccess) {
          this.notify.success(id ? 'Student updated.' : 'Student admitted.');
          const newId = id ?? (res.data as { student_id?: number } | null)?.student_id;
          void this.router.navigate(newId ? ['/students', newId] : ['/students']);
        } else {
          // Keep entered data; show a meaningful message.
          this.notify.error(res.resultCodeDescription ?? 'Could not save the student.');
        }
      },
      error: () => {
        this.saving.set(false);
        this.notify.error('A network or server error occurred. Your changes were not lost.');
      }
    });
  }

  protected cancel(): void {
    const id = this.studentId();
    void this.router.navigate(id ? ['/students', id] : ['/students']);
  }
}

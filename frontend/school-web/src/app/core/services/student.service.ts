import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  ApiResponse,
  Enrollment,
  GraduateRequest,
  ItemsData,
  PromoteRequest,
  Student,
  StudentDetail,
  StudentImportPreview,
  StudentImportResult,
  StudentImportRow,
  StudentListQuery,
  StudentPage,
  StudentStatusRequest,
  StudentSummary,
  StudentUpsert,
  WithdrawRequest
} from '../models/api.models';

/** Typed client for the Students module. Unwraps the ApiResponse envelope. */
@Injectable({ providedIn: 'root' })
export class StudentService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/students`;

  list(q: StudentListQuery): Observable<StudentPage | null> {
    let p = new HttpParams()
      .set('page', q.page ?? 1)
      .set('pageSize', q.pageSize ?? 20);
    if (q.search) p = p.set('search', q.search);
    if (q.classId) p = p.set('classId', q.classId);
    if (q.sectionId) p = p.set('sectionId', q.sectionId);
    if (q.academicYearId) p = p.set('academicYearId', q.academicYearId);
    if (q.status) p = p.set('status', q.status);
    if (q.sortBy) p = p.set('sortBy', q.sortBy);
    if (q.sortDir) p = p.set('sortDir', q.sortDir);
    return this.http
      .get<ApiResponse<StudentPage>>(this.base, { params: p })
      .pipe(map((r) => r.data));
  }

  summary(): Observable<StudentSummary | null> {
    return this.http
      .get<ApiResponse<StudentSummary>>(`${this.base}/summary`)
      .pipe(map((r) => r.data));
  }

  get(id: number): Observable<StudentDetail | null> {
    return this.http
      .get<ApiResponse<StudentDetail>>(`${this.base}/${id}`)
      .pipe(map((r) => r.data));
  }

  create(body: StudentUpsert): Observable<ApiResponse<{ student_id: number; admission_number: string }>> {
    return this.http.post<ApiResponse<{ student_id: number; admission_number: string }>>(this.base, body);
  }

  update(id: number, body: StudentUpsert): Observable<ApiResponse<unknown>> {
    return this.http.put<ApiResponse<unknown>>(`${this.base}/${id}`, body);
  }

  setStatus(id: number, body: StudentStatusRequest): Observable<ApiResponse<unknown>> {
    return this.http.post<ApiResponse<unknown>>(`${this.base}/${id}/status`, body);
  }

  /** Soft-delete (deactivate -> status Inactive). */
  deactivate(id: number): Observable<ApiResponse<unknown>> {
    return this.http.delete<ApiResponse<unknown>>(`${this.base}/${id}`);
  }

  deactivateStudent(s: Student): Observable<ApiResponse<unknown>> {
    return this.deactivate(s.student_id);
  }

  // ---- Enrollment history + academic progression ----
  enrollments(id: number): Observable<Enrollment[]> {
    return this.http
      .get<ApiResponse<ItemsData<Enrollment>>>(`${this.base}/${id}/enrollments`)
      .pipe(map((r) => r.data?.items ?? []));
  }

  promote(body: PromoteRequest): Observable<ApiResponse<{ promoted: number }>> {
    return this.http.post<ApiResponse<{ promoted: number }>>(`${this.base}/promote`, body);
  }

  graduate(body: GraduateRequest): Observable<ApiResponse<{ graduated: number }>> {
    return this.http.post<ApiResponse<{ graduated: number }>>(`${this.base}/graduate`, body);
  }

  withdraw(body: WithdrawRequest): Observable<ApiResponse<{ withdrawn: number }>> {
    return this.http.post<ApiResponse<{ withdrawn: number }>>(`${this.base}/withdraw`, body);
  }

  // ---- Bulk import ----

  /** Download the blank import template as an .xlsx (via HttpClient so the auth token is attached). */
  downloadTemplate(): Observable<Blob> {
    return this.http.get(`${this.base}/import/template`, { responseType: 'blob' });
  }

  /** Upload a filled template and get a validated preview (no DB write). */
  importPreview(file: File): Observable<StudentImportPreview | null> {
    const fd = new FormData();
    fd.append('file', file);
    return this.http
      .post<ApiResponse<StudentImportPreview>>(`${this.base}/import`, fd)
      .pipe(map((r) => r.data));
  }

  /** Create the chosen rows as new students. */
  commitImport(rows: StudentImportRow[]): Observable<StudentImportResult | null> {
    return this.http
      .post<ApiResponse<StudentImportResult>>(`${this.base}/import/commit`, { Rows: rows })
      .pipe(map((r) => r.data));
  }
}

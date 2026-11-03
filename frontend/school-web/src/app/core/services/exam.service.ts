import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  ApiResponse,
  Exam,
  ExamClassSubjectsRequest,
  ExamDetail,
  ExamListQuery,
  ExamMarksSaveRequest,
  ExamMarksSheet,
  ExamScheduleRow,
  ExamScheduleSaveRequest,
  ExamSubjectAdd,
  ExamSubjectOption,
  ExamSubjectRow,
  ExamUpsert,
  ImportPreview,
  ItemsData,
  ReportCard,
  ReportCardList,
  ResultPreview
} from '../models/api.models';

/** Typed client for the Exams and Report Cards module. */
@Injectable({ providedIn: 'root' })
export class ExamService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/exams`;

  list(q: ExamListQuery = {}): Observable<Exam[]> {
    let p = new HttpParams();
    if (q.search) p = p.set('search', q.search);
    if (q.classId) p = p.set('classId', q.classId);
    if (q.academicYearId) p = p.set('academicYearId', q.academicYearId);
    if (q.status) p = p.set('status', q.status);
    if (q.examType) p = p.set('examType', q.examType);
    return this.http
      .get<ApiResponse<ItemsData<Exam>>>(this.base, { params: p })
      .pipe(map((r) => r.data?.items ?? []));
  }

  get(examId: number): Observable<ExamDetail | null> {
    return this.http
      .get<ApiResponse<ExamDetail>>(`${this.base}/${examId}`)
      .pipe(map((r) => r.data));
  }

  save(body: ExamUpsert): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(this.base, body);
  }

  addSubject(body: ExamSubjectAdd): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/subjects`, body);
  }

  // ---- Wizard step 2: class subjects ----
  saveClassSubjects(body: ExamClassSubjectsRequest): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/class-subjects`, body);
  }

  classSubjects(examId: number, classId?: number): Observable<ExamSubjectRow[]> {
    let p = new HttpParams();
    if (classId) p = p.set('classId', classId);
    return this.http
      .get<ApiResponse<ItemsData<ExamSubjectRow>>>(`${this.base}/${examId}/class-subjects`, { params: p })
      .pipe(map((r) => r.data?.items ?? []));
  }

  // ---- Wizard step 3: schedule ----
  saveSchedule(body: ExamScheduleSaveRequest): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/schedule`, body);
  }

  schedule(examId: number, classId?: number): Observable<ExamScheduleRow[]> {
    let p = new HttpParams();
    if (classId) p = p.set('classId', classId);
    return this.http
      .get<ApiResponse<ItemsData<ExamScheduleRow>>>(`${this.base}/${examId}/schedule`, { params: p })
      .pipe(map((r) => r.data?.items ?? []));
  }

  subjectsForClass(examId: number, classId: number): Observable<ExamSubjectOption[]> {
    return this.http
      .get<ApiResponse<ItemsData<ExamSubjectOption>>>(`${this.base}/${examId}/classes/${classId}/subjects`)
      .pipe(map((r) => r.data?.items ?? []));
  }

  marksSheet(examSubjectId: number, sectionId?: number): Observable<ExamMarksSheet | null> {
    let p = new HttpParams();
    if (sectionId) p = p.set('sectionId', sectionId);
    return this.http
      .get<ApiResponse<ExamMarksSheet>>(`${this.base}/subjects/${examSubjectId}/sheet`, { params: p })
      .pipe(map((r) => r.data));
  }

  /** URL for the Excel template download (opened in a new tab / via anchor). */
  templateUrl(examSubjectId: number, sectionId?: number): string {
    const q = sectionId ? `?sectionId=${sectionId}` : '';
    return `${this.base}/subjects/${examSubjectId}/template${q}`;
  }

  importMarks(examSubjectId: number, file: File, sectionId?: number): Observable<ImportPreview | null> {
    const form = new FormData();
    form.append('file', file);
    const q = sectionId ? `?sectionId=${sectionId}` : '';
    return this.http
      .post<ApiResponse<ImportPreview>>(`${this.base}/subjects/${examSubjectId}/import${q}`, form)
      .pipe(map((r) => r.data));
  }

  saveMarks(body: ExamMarksSaveRequest): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/marks`, body);
  }

  publish(examId: number, publish: boolean, force = false): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/publish`, { ExamId: examId, Publish: publish, Force: force });
  }

  resultPreview(examId: number, classId: number, sectionId?: number): Observable<ResultPreview | null> {
    let p = new HttpParams();
    if (sectionId) p = p.set('sectionId', sectionId);
    return this.http
      .get<ApiResponse<ResultPreview>>(`${this.base}/${examId}/classes/${classId}/results`, { params: p })
      .pipe(map((r) => r.data));
  }

  reportCard(examId: number, studentId: number): Observable<ReportCard | null> {
    return this.http
      .get<ApiResponse<ReportCard>>(`${this.base}/${examId}/report-card/${studentId}`)
      .pipe(map((r) => r.data));
  }

  reportCardList(examId: number, classId: number, sectionId?: number): Observable<ReportCardList | null> {
    let p = new HttpParams();
    if (sectionId) p = p.set('sectionId', sectionId);
    return this.http
      .get<ApiResponse<ReportCardList>>(`${this.base}/${examId}/classes/${classId}/report-cards`, { params: p })
      .pipe(map((r) => r.data));
  }
}

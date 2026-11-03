import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import { ApiResponse, AttendanceMarkRequest, AttendanceSheet, AttendanceTodaySummary, AttendanceHistoryRow, ItemsData } from '../models/api.models';

/** Typed client for the Attendance module. */
@Injectable({ providedIn: 'root' })
export class AttendanceService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/attendance`;

  sheet(classId: number, date: string, sectionId?: number, subjectId?: number): Observable<AttendanceSheet | null> {
    let p = new HttpParams().set('classId', classId).set('date', date);
    if (sectionId) p = p.set('sectionId', sectionId);
    if (subjectId) p = p.set('subjectId', subjectId);
    return this.http.get<ApiResponse<AttendanceSheet>>(`${this.base}/sheet`, { params: p }).pipe(map((r) => r.data));
  }

  mark(body: AttendanceMarkRequest): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/mark`, body);
  }

  today(date?: string): Observable<AttendanceTodaySummary | null> {
    let p = new HttpParams();
    if (date) p = p.set('date', date);
    return this.http.get<ApiResponse<AttendanceTodaySummary>>(`${this.base}/today`, { params: p }).pipe(map((r) => r.data));
  }

  /** A single student's attendance history (most recent first). */
  history(studentId: number, limit = 60): Observable<AttendanceHistoryRow[]> {
    const p = new HttpParams().set('limit', limit);
    return this.http
      .get<ApiResponse<ItemsData<AttendanceHistoryRow>>>(`${this.base}/history/${studentId}`, { params: p })
      .pipe(map((r) => r.data?.items ?? []));
  }
}

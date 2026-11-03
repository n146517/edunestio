import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  ApiResponse,
  Student,
  StudentPage,
  StudentUpsert,
  StatusData
} from '../models/api.models';

/** Thin typed client over the EduNestIO API. Unwraps the ApiResponse envelope. */
@Injectable({ providedIn: 'root' })
export class ApiService {
  private readonly http = inject(HttpClient);
  private readonly base = environment.apiBaseUrl;

  getStatus(): Observable<StatusData | null> {
    return this.http.get<ApiResponse<StatusData>>(`${this.base}/status`).pipe(map((r) => r.data));
  }

  listStudents(params: {
    search?: string;
    classId?: number;
    status?: string;
    page?: number;
    pageSize?: number;
  }): Observable<StudentPage | null> {
    let hp = new HttpParams()
      .set('page', params.page ?? 1)
      .set('pageSize', params.pageSize ?? 20);
    if (params.search) hp = hp.set('search', params.search);
    if (params.classId) hp = hp.set('classId', params.classId);
    if (params.status) hp = hp.set('status', params.status);
    return this.http
      .get<ApiResponse<StudentPage>>(`${this.base}/students`, { params: hp })
      .pipe(map((r) => r.data));
  }

  getStudent(id: number): Observable<Student | null> {
    return this.http.get<ApiResponse<Student>>(`${this.base}/students/${id}`).pipe(map((r) => r.data));
  }

  createStudent(body: StudentUpsert): Observable<ApiResponse<unknown>> {
    return this.http.post<ApiResponse<unknown>>(`${this.base}/students`, body);
  }

  updateStudent(id: number, body: StudentUpsert): Observable<ApiResponse<unknown>> {
    return this.http.put<ApiResponse<unknown>>(`${this.base}/students/${id}`, body);
  }

  deleteStudent(id: number): Observable<ApiResponse<unknown>> {
    return this.http.delete<ApiResponse<unknown>>(`${this.base}/students/${id}`);
  }
}

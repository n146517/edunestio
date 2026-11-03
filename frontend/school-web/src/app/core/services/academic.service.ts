import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  ApiResponse, ItemsData, SchoolClass, ClassUpsert, Section, SectionUpsert,
  Subject, SubjectUpsert, AcademicYear, AcademicYearUpsert
} from '../models/api.models';

/** Typed client for the Academic Setup module. Unwraps the ApiResponse envelope. */
@Injectable({ providedIn: 'root' })
export class AcademicService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/academic`;

  listYears(): Observable<AcademicYear[]> {
    return this.http.get<ApiResponse<ItemsData<AcademicYear>>>(`${this.base}/years`).pipe(map((r) => r.data?.items ?? []));
  }
  saveYear(body: AcademicYearUpsert): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/years`, body);
  }

  listClasses(): Observable<SchoolClass[]> {
    return this.http.get<ApiResponse<ItemsData<SchoolClass>>>(`${this.base}/classes`).pipe(map((r) => r.data?.items ?? []));
  }
  saveClass(body: ClassUpsert): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/classes`, body);
  }

  listSections(classId?: number): Observable<Section[]> {
    let p = new HttpParams();
    if (classId) p = p.set('classId', classId);
    return this.http.get<ApiResponse<ItemsData<Section>>>(`${this.base}/sections`, { params: p }).pipe(map((r) => r.data?.items ?? []));
  }
  saveSection(body: SectionUpsert): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/sections`, body);
  }

  listSubjects(): Observable<Subject[]> {
    return this.http.get<ApiResponse<ItemsData<Subject>>>(`${this.base}/subjects`).pipe(map((r) => r.data?.items ?? []));
  }
  saveSubject(body: SubjectUpsert): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/subjects`, body);
  }
}

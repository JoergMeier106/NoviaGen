import 'package:dio/dio.dart';

abstract class ApiClientTransport {
  Dio get dio;
}

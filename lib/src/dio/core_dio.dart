import 'dart:io';

import 'package:busenet/busenet.dart';
import 'package:dio/io.dart';

import '../utility/helper_functions.dart';

part '../parted_methods/model_parser.dart';
part '../parted_methods/error_handler.dart';

class CoreDio<T extends BaseResponse<T>> with DioMixin implements Dio, ICoreDio<T> {
  late CacheOptions cacheOptions;
  late T responseModel;
  String? entityKey;
  late bool isLoggerEnabled;

  ErrorMessages? errorMessages;

  CoreDio(BaseOptions options, this.cacheOptions, this.responseModel, this.entityKey, {this.isLoggerEnabled = true, this.errorMessages}) {
    this.options = options;
    httpClientAdapter = IOHttpClientAdapter();
  }

  @override
  Future<T> send<E extends BaseEntity<E>, R>(
    String path, {
    required E parserModel,
    required HttpTypes type,
    String contentType = Headers.jsonContentType,
    ResponseType responseType = ResponseType.json,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,

    /// Cache Options
    CachePolicy? cachePolicy,
    Duration? maxStale,

    // Entity Options
    bool ignoreEntityKey = false,
    String? insideEntityKey,
  }) async {
    try {
      final response = await request<dynamic>(
        path,
        data: data,
        options: cacheOptions
            .copyWith(
              policy: cachePolicy,
              maxStale: Nullable<Duration>(maxStale),
            )
            .toOptions()
            .copyWith(
              method: type.value,
              contentType: contentType,
              responseType: responseType,
            ),
        queryParameters: queryParameters,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );

      if (isLoggerEnabled) {
        customPrint(
          fromWhere: 'CoreDio',
          type: 'send - http statusCode',
          data: '${response.statusCode} - ${DateTime.now()}',
        );
      }

      switch (response.statusCode) {
        case HttpStatus.ok:
        case HttpStatus.accepted:
        case HttpStatus.notModified: // 304 : Cache Policy is used and data is not modified since last request (maxStale)

          final entity = _parseBody<E, R>(
            response.data,
            model: parserModel,
            entityKey: entityKey,
            insideEntityKey: insideEntityKey,
          );

          if (responseModel is! EmptyResponseModel) {
            responseModel = responseModel.fromJson(response.data as Map<String, dynamic>);
          }

          if (ignoreEntityKey) {
            responseModel.setData(response.data);
          } else {
            responseModel.setData(entity);
          }
          responseModel.statusCode = 1;
          return responseModel;
        case 401:
          final model = responseModel.fromJson(response.data);
          model.errorType = UnAuthorizedFailure();
          return model;
        case 404:
          final model = responseModel.fromJson(response.data);
          model.errorType = NotFoundFailure();
          return model;
        default:
          responseModel = responseModel.fromJson(response.data as Map<String, dynamic>);
          responseModel.statusCode = response.statusCode;
          return responseModel;
      }
    } catch (error) {
      responseModel.statusCode = -1;
      if (error is DioExceptionType) {
        responseModel.errorType = handleError(error, errorMessages);
      } else {
        responseModel.errorType = UnknownFailure();
      }
      return responseModel;
    }
  }

  @override
  void addHeader(Map<String, dynamic> value) {
    options.headers.addAll(value);
  }

  @override
  void removeHeader(String key) {
    options.headers.remove(key);
  }

  @override
  void addAuthorizationHeader(String token) {
    options.headers.addAll({'Authorization': 'Bearer $token'});
  }

  @override
  void removeAuthorizationHeader() {
    options.headers.remove('Authorization');
  }

  @override
  void addInterceptor(Interceptor interceptor) {
    interceptors.add(interceptor);
  }
}

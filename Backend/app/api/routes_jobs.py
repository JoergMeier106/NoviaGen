from __future__ import annotations

from flask import Response, current_app, request

from .blueprint import api
from .chat_requests import (
    chat_request_body as _chat_request_body,
    is_multipart_request as _is_multipart_request,
)
from .job_responses import (
    cancel_all_jobs_response as _cancel_all_jobs_response,
    cancel_job_response as _cancel_job_response,
    clear_finished_jobs_response as _clear_finished_jobs_response,
    create_animate_image_job_response as _create_animate_image_job_response,
    create_chat_message_job_response as _create_chat_message_job_response,
    create_convert_video_to_gif_job_response as _create_convert_video_to_gif_job_response,
    create_generate_audio_video_job_response as _create_generate_audio_video_job_response,
    create_generate_from_image_job_response as _create_generate_from_image_job_response,
    create_generate_i2v_prompt_job_response as _create_generate_i2v_prompt_job_response,
    create_generate_job_response as _create_generate_job_response,
    create_generate_prompt_job_response as _create_generate_prompt_job_response,
    create_generate_video_job_response as _create_generate_video_job_response,
    create_upscale_job_response as _create_upscale_job_response,
    create_upscale_video_job_response as _create_upscale_video_job_response,
    get_job_response as _get_job_response,
    list_jobs_response as _list_jobs_response,
)
from .media import is_still_media as _is_still_media
from .route_context import (
    catalog as _catalog,
    chat_context_images as _chat_context_images,
    db as _db,
    worker as _worker,
)


@api.post("/api/jobs/generate-prompt")
def create_generate_prompt_job() -> Response:
    return _create_generate_prompt_job_response(
        body=request.get_json(silent=True) or {},
        db=_db(),
        worker=_worker(),
    )


@api.post("/api/jobs/generate-i2v-prompt")
def create_generate_i2v_prompt_job() -> Response:
    return _create_generate_i2v_prompt_job_response(
        request_obj=request,
        db=_db(),
        worker=_worker(),
        temp_dir=current_app.config["TEMP_DIR"],
        is_still_media=_is_still_media,
    )


@api.post("/api/jobs/chat-message")
def create_chat_message_job() -> Response:
    is_multipart = _is_multipart_request(request)
    body = _chat_request_body(request, is_multipart=is_multipart)
    return _create_chat_message_job_response(
        request_obj=request,
        body=body,
        is_multipart=is_multipart,
        db=_db(),
        worker=_worker(),
        context_images=_chat_context_images(),
    )


@api.post("/api/jobs/generate")
def create_generate_job() -> Response:
    return _create_generate_job_response(
        body=request.get_json(silent=True) or {},
        catalog=_catalog(),
        db=_db(),
        worker=_worker(),
    )


@api.post("/api/jobs/upscale")
def create_upscale_job() -> Response:
    return _create_upscale_job_response(
        body=request.get_json(silent=True) or {},
        db=_db(),
        worker=_worker(),
    )


@api.post("/api/jobs/upscale-video")
def create_upscale_video_job() -> Response:
    return _create_upscale_video_job_response(
        body=request.get_json(silent=True) or {},
        db=_db(),
        worker=_worker(),
        config=current_app.config,
    )


@api.post("/api/jobs/convert-video-gif")
def create_convert_video_to_gif_job() -> Response:
    return _create_convert_video_to_gif_job_response(
        body=request.get_json(silent=True) or {},
        db=_db(),
        worker=_worker(),
    )


@api.post("/api/jobs/generate-audio-video")
def create_generate_audio_video_job() -> Response:
    return _create_generate_audio_video_job_response(
        body=request.get_json(silent=True) or {},
        db=_db(),
        worker=_worker(),
        config=current_app.config,
    )


@api.post("/api/jobs/generate-from-image")
def create_generate_from_image_job() -> Response:
    return _create_generate_from_image_job_response(
        request_obj=request,
        catalog=_catalog(),
        db=_db(),
        worker=_worker(),
        temp_dir=current_app.config["TEMP_DIR"],
        is_still_media=_is_still_media,
    )


@api.post("/api/jobs/generate-video")
def create_generate_video_job() -> Response:
    return _create_generate_video_job_response(
        body=request.get_json(silent=True) or {},
        db=_db(),
        worker=_worker(),
        config=current_app.config,
    )


@api.post("/api/jobs/animate-image")
def create_animate_image_job() -> Response:
    return _create_animate_image_job_response(
        request_obj=request,
        db=_db(),
        worker=_worker(),
        temp_dir=current_app.config["TEMP_DIR"],
        is_still_media=_is_still_media,
        config=current_app.config,
    )


@api.get("/api/jobs")
def list_jobs() -> Response:
    return _list_jobs_response(
        request_args=request.args,
        db=_db(),
        worker=_worker(),
    )


@api.delete("/api/jobs")
def clear_jobs() -> Response:
    return _clear_finished_jobs_response(
        db=_db(),
        scope=str(request.args.get("scope") or ""),
    )


@api.post("/api/jobs/cancel")
def cancel_all_jobs() -> Response:
    return _cancel_all_jobs_response(worker=_worker())


@api.get("/api/jobs/<job_id>")
def get_job(job_id: str) -> Response:
    return _get_job_response(job_id=job_id, db=_db(), worker=_worker())


@api.post("/api/jobs/<job_id>/cancel")
def cancel_job(job_id: str) -> Response:
    return _cancel_job_response(job_id=job_id, worker=_worker())

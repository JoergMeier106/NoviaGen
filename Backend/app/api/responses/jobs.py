from __future__ import annotations

from typing import Any

from flask import Response, jsonify

from ..requests.chat import (
    chat_context_image_ids,
    chat_uploaded_files,
    is_multipart_request,
)
from ..payloads.jobs import job_payload
from ..requests.jobs import (
    JobRequestError,
    animate_image_payload,
    chat_message_payload,
    chain_payload,
    generate_from_image_payload,
    generate_i2v_prompt_payload,
    generate_payload,
    generate_prompt_payload,
    generate_video_payload,
    upscale_payload,
    video_to_audio_payload,
    video_to_gif_payload,
    video_upscale_payload,
)
from ..requests.parsing import normalized_optional_bool, normalized_optional_int
from ...generation import OllamaResponseError, OllamaUnavailableError


def create_generate_prompt_job_response(
    *,
    body: dict[str, Any],
    db: Any,
    worker: Any,
) -> Response | tuple[Response, int]:
    generator = getattr(worker, "generator", None)
    if generator is None or not hasattr(generator, "generate_prompt"):
        return jsonify({"error": "Prompt generation is not available"}), 503
    try:
        payload = generate_prompt_payload(body)
    except JobRequestError as exc:
        return _job_request_error(exc)
    job_id = worker.enqueue_generate_prompt(payload)
    return queued_job_response(job_id=job_id, db=db)


def create_generate_i2v_prompt_job_response(
    *,
    request_obj: Any,
    db: Any,
    worker: Any,
    temp_dir: str,
    is_still_media,
) -> Response | tuple[Response, int]:
    body, uploaded_file = _multipart_image_parts(request_obj)
    try:
        payload = generate_i2v_prompt_payload(
            body=body,
            uploaded_file=uploaded_file,
            db=db,
            temp_dir=temp_dir,
            is_still_media=is_still_media,
        )
    except JobRequestError as exc:
        return _job_request_error(exc)
    job_id = worker.enqueue_generate_i2v_prompt(payload)
    return queued_job_response(job_id=job_id, db=db)


def create_chat_message_job_response(
    *,
    request_obj: Any,
    body: dict[str, Any],
    is_multipart: bool,
    db: Any,
    worker: Any,
    context_images: Any,
    mcp_tool_provider: Any = None,
    ollama_client: Any = None,
) -> Response | tuple[Response, int]:
    generator = getattr(worker, "generator", None)
    if generator is None:
        return jsonify({"error": "Chat is not available"}), 503

    try:
        payload = chat_message_payload(
            body=body,
            request_obj=request_obj,
            is_multipart=is_multipart,
            db=db,
            context_images=context_images,
            chat_context_image_ids=chat_context_image_ids,
            chat_uploaded_files=chat_uploaded_files,
            normalized_optional_bool=_normalized_think,
            normalized_optional_int=_normalized_context_window,
        )
    except JobRequestError as exc:
        return _job_request_error(exc)
    try:
        payload["enabled_tool_ids"] = _resolved_enabled_tool_ids(
            payload=payload,
            mcp_tool_provider=mcp_tool_provider,
        )
        _validate_tool_model_support(
            payload=payload,
            ollama_client=ollama_client,
        )
    except JobRequestError as exc:
        return _job_request_error(exc)
    job_id = worker.enqueue_chat_message(payload)
    return queued_job_response(job_id=job_id, db=db)


def create_chain_job_response(
    *,
    request_obj: Any,
    catalog: Any,
    db: Any,
    worker: Any,
    temp_dir: str,
    is_still_media,
    config: dict[str, Any],
) -> Response | tuple[Response, int]:
    try:
        payload = chain_payload(
            request_obj=request_obj,
            catalog=catalog,
            db=db,
            temp_dir=temp_dir,
            is_still_media=is_still_media,
            config=config,
        )
    except JobRequestError as exc:
        return _job_request_error(exc)
    job_id = worker.enqueue_chain(payload)
    return queued_job_response(job_id=job_id, db=db)


def create_generate_job_response(
    *,
    body: dict[str, Any],
    catalog: Any,
    db: Any,
    worker: Any,
) -> Response | tuple[Response, int]:
    try:
        payload = generate_payload(body=body, catalog=catalog)
    except JobRequestError as exc:
        return _job_request_error(exc)
    job_id = worker.enqueue_generate(payload)
    return queued_job_response(job_id=job_id, db=db)


def create_upscale_job_response(
    *,
    body: dict[str, Any],
    db: Any,
    worker: Any,
) -> Response | tuple[Response, int]:
    try:
        payload = upscale_payload(body=body, db=db)
    except JobRequestError as exc:
        return _job_request_error(exc)
    job_id = worker.enqueue_upscale(payload)
    return queued_job_response(job_id=job_id, db=db)


def create_upscale_video_job_response(
    *,
    body: dict[str, Any],
    db: Any,
    worker: Any,
    config: dict[str, Any],
) -> Response | tuple[Response, int]:
    try:
        payload = video_upscale_payload(body=body, db=db, config=config)
    except JobRequestError as exc:
        return _job_request_error(exc)
    job_id = worker.enqueue_upscale_video(payload)
    return queued_job_response(job_id=job_id, db=db)


def create_convert_video_to_gif_job_response(
    *,
    body: dict[str, Any],
    db: Any,
    worker: Any,
) -> Response | tuple[Response, int]:
    try:
        payload = video_to_gif_payload(body=body, db=db)
    except JobRequestError as exc:
        return _job_request_error(exc)
    job_id = worker.enqueue_convert_video_to_gif(payload)
    return queued_job_response(job_id=job_id, db=db)


def create_generate_audio_video_job_response(
    *,
    body: dict[str, Any],
    db: Any,
    worker: Any,
    config: dict[str, Any],
) -> Response | tuple[Response, int]:
    try:
        payload = video_to_audio_payload(body=body, db=db, config=config)
    except JobRequestError as exc:
        return _job_request_error(exc)
    job_id = worker.enqueue_generate_audio_video(payload)
    return queued_job_response(job_id=job_id, db=db)


def create_generate_from_image_job_response(
    *,
    request_obj: Any,
    catalog: Any,
    db: Any,
    worker: Any,
    temp_dir: str,
    is_still_media,
) -> Response | tuple[Response, int]:
    body, uploaded_file = _multipart_image_parts(request_obj)
    try:
        payload = generate_from_image_payload(
            body=body,
            uploaded_file=uploaded_file,
            is_multipart=_is_multipart(request_obj),
            catalog=catalog,
            db=db,
            temp_dir=temp_dir,
            is_still_media=is_still_media,
        )
    except JobRequestError as exc:
        return _job_request_error(exc)

    job_id = worker.enqueue_generate_from_image(payload)
    return queued_job_response(job_id=job_id, db=db)


def create_generate_video_job_response(
    *,
    body: dict[str, Any],
    db: Any,
    worker: Any,
    config: dict[str, Any],
) -> Response | tuple[Response, int]:
    try:
        payload = generate_video_payload(body=body, config=config)
    except JobRequestError as exc:
        return _job_request_error(exc)
    job_id = worker.enqueue_generate_video(payload)
    return queued_job_response(job_id=job_id, db=db)


def create_animate_image_job_response(
    *,
    request_obj: Any,
    db: Any,
    worker: Any,
    temp_dir: str,
    is_still_media,
    config: dict[str, Any],
) -> Response | tuple[Response, int]:
    body, uploaded_file = _multipart_image_parts(request_obj)
    try:
        payload = animate_image_payload(
            body=body,
            uploaded_file=uploaded_file,
            db=db,
            temp_dir=temp_dir,
            is_still_media=is_still_media,
            config=config,
        )
    except JobRequestError as exc:
        return _job_request_error(exc)
    job_id = worker.enqueue_animate_image(payload)
    return queued_job_response(job_id=job_id, db=db)


def list_jobs_response(
    *,
    request_args: Any,
    db: Any,
    worker: Any,
) -> Response | tuple[Response, int]:
    worker.ensure_processing()
    try:
        page = max(1, int(request_args.get("page", 1)))
        page_size = max(1, min(200, int(request_args.get("page_size", 50))))
    except ValueError:
        return jsonify({"error": "page and page_size must be integers"}), 400

    listing = db.list_jobs(
        page=page,
        page_size=page_size,
        status=request_args.get("status") or None,
    )
    return jsonify(
        {
            "items": [
                job_payload(item, include_result=True)
                for item in listing["items"]
            ],
            "page": listing["page"],
            "page_size": listing["page_size"],
            "total": listing["total"],
        }
    )


def clear_finished_jobs_response(*, db: Any, scope: str) -> Response | tuple[Response, int]:
    if str(scope or "").strip().lower() != "finished":
        return jsonify({"error": "scope must be 'finished'"}), 400

    deleted = db.delete_jobs_by_statuses({"completed", "failed", "cancelled"})
    return jsonify({"deleted": deleted})


def get_job_response(
    *,
    job_id: str,
    db: Any,
    worker: Any,
) -> Response | tuple[Response, int]:
    worker.ensure_processing()
    job = db.get_job(job_id)
    if job is None:
        return jsonify({"error": "Job not found"}), 404
    return jsonify(job_payload(job, include_result=True))


def cancel_job_response(*, job_id: str, worker: Any) -> Response | tuple[Response, int]:
    job = worker.cancel(job_id)
    if job is None:
        return jsonify({"error": "Job not found"}), 404
    return jsonify(job_payload(job))


def cancel_all_jobs_response(*, worker: Any) -> Response:
    jobs = worker.cancel_all()
    return jsonify(
        {
            "cancelled": len(jobs),
            "items": [job_payload(job) for job in jobs],
        }
    )


def inter_job_delay_response(*, body: dict[str, Any], worker: Any) -> Response | tuple[Response, int]:
    try:
        seconds = int(body.get("seconds", 0))
    except (TypeError, ValueError):
        return jsonify({"error": "seconds must be an integer"}), 400
    if seconds < 0 or seconds > 3600:
        return jsonify({"error": "seconds must be between 0 and 3600"}), 400
    return jsonify(worker.set_inter_job_delay_seconds(seconds))


def queued_job_response(*, job_id: str, db: Any) -> Response | tuple[Response, int]:
    job = db.get_job(job_id)
    if job is None:
        return jsonify({"error": "Job not found"}), 500
    return jsonify(job_payload(job, include_result=True)), 202


def _job_request_error(exc: JobRequestError) -> tuple[Response, int]:
    return jsonify({"error": str(exc)}), exc.status_code


def _multipart_image_parts(request_obj: Any) -> tuple[dict[str, Any], Any]:
    if _is_multipart(request_obj):
        return dict(request_obj.form), request_obj.files.get("image")
    return request_obj.get_json(silent=True) or {}, None


def _is_multipart(request_obj: Any) -> bool:
    return bool(
        request_obj.content_type
        and "multipart/form-data" in request_obj.content_type.lower()
    )


def _normalized_context_window(value: Any) -> int | None:
    return normalized_optional_int(value, field_name="context_window")


def _resolved_enabled_tool_ids(
    *,
    payload: dict[str, Any],
    mcp_tool_provider: Any,
) -> list[str]:
    enabled_tool_ids = [
        str(item).strip()
        for item in payload.get("enabled_tool_ids", [])
        if str(item).strip()
    ]
    if enabled_tool_ids and mcp_tool_provider is None:
        raise JobRequestError("Chat MCP tools are not configured.", status_code=503)
    if enabled_tool_ids:
        try:
            mcp_tool_provider.toolset_for_ids(enabled_tool_ids)
        except Exception as exc:
            raise JobRequestError(str(exc), status_code=503) from exc
    return enabled_tool_ids


def _validate_tool_model_support(
    *,
    payload: dict[str, Any],
    ollama_client: Any,
) -> None:
    if not payload.get("enabled_tool_ids"):
        return
    if ollama_client is None:
        raise JobRequestError("Could not validate Ollama tool support.", status_code=503)
    try:
        show_payload = ollama_client.show_model(str(payload.get("model_name") or ""))
    except OllamaUnavailableError as exc:
        raise JobRequestError(str(exc), status_code=503) from exc
    except OllamaResponseError as exc:
        raise JobRequestError(str(exc), status_code=502) from exc
    capabilities = {
        str(item).strip().lower()
        for item in show_payload.get("capabilities", [])
        if str(item).strip()
    }
    if "tools" not in capabilities:
        raise JobRequestError(
            "Selected Ollama model does not support tools.",
            status_code=400,
        )


def _normalized_think(value: Any) -> bool | None:
    return normalized_optional_bool(value, field_name="think")

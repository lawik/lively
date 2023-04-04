defmodule Lively.Media.Face do
  alias Evision.VideoCapture

  @video_device 0
  def open do
    # VideoCapture.videoCapture(@video_device)
    VideoCapture.videoCapture(@video_device)
  end

  def snap(device) do
    VideoCapture.read(device)
  end

  def save_png(cap, path) do
    Evision.imwrite(path, cap)
  end

  def detect(image) do
    opts = [
      top_k: 5000,
      nms_threshold: 0.3,
      conf_threshold: 0.9,
      backend: Evision.Constant.cv_DNN_BACKEND_OPENCV(),
      target: Evision.Constant.cv_DNN_TARGET_CPU()
    ]

    model = Evision.Zoo.FaceDetection.YuNet.init(:quant_model, opts)

    results = Evision.Zoo.FaceDetection.YuNet.infer(model, image)

    landmark_names = [
      # right eye
      :right_eye,
      # left eye
      :left_eye,
      # nose tip
      :nose_tip,
      # right mouth corner
      :right_mouth_corner,
      # left mouth corner
      :left_mouth_corner
    ]

    IO.inspect(results)

    if results do
      faces =
        case results.shape do
          {num_faces, 15} when num_faces > 0 ->
            results = Evision.Mat.to_nx(results, Nx.BinaryBackend)

            for i <- 0..(num_faces - 1) do
              det = results[i]
              [b0, b1, b2, b3] = Nx.to_flat_list(Nx.as_type(det[0..3], :s32))

              face = %{
                face_top_left: {b0, b1},
                face_bottom_right: {b0 + b2, b1 + b3}
              }

              landmarks = Nx.reshape(Nx.as_type(det[4..13], :s32), {5, 2})

              for idx <- 0..4, into: face do
                landmark = List.to_tuple(Nx.to_flat_list(landmarks[idx]))
                {Enum.at(landmark_names, idx), landmark}
              end
            end

          _ ->
            []
        end

      save_png(image, "priv/static/assets/face.png")

      %{
        dimensions: {elem(image.shape, 1), elem(image.shape, 0)},
        faces: faces,
        path: "assets/face.png"
      }
    else
      %{
        dimensions: {elem(image.shape, 1), elem(image.shape, 0)},
        faces: [],
        path: nil
      }
    end
  end
end

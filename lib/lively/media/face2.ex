defmodule Lively.Media.Face2 do
  alias Evision.VideoCapture

  @video_device 0
  def open do
    # VideoCapture.videoCapture(@video_device)
    device = VideoCapture.videoCapture(@video_device)

    face_cascade = Evision.CascadeClassifier.cascadeClassifier()

    cascade_name =
      Path.join([
        "#{:code.priv_dir(:evision)}",
        "share/opencv4/lbpcascades/lbpcascade_frontalface.xml"
      ])

    true = Evision.CascadeClassifier.load(face_cascade, cascade_name)
    facemark = Evision.Face.createFacemarkKazemi()
    # https://github.com/opencv/opencv_3rdparty/tree/contrib_face_alignment_20170818
    facemark = Evision.Face.Facemark.loadModel(facemark, "priv/faces/face_landmark_model.dat")
    {device, {face_cascade, facemark}}
  end

  def snap(device) do
    VideoCapture.read(device)
  end

  def save_png(cap, path) do
    Evision.imwrite(path, cap)
  end

  def detect(image, {cascade, model}) do
    img =
      Evision.resize(image, {460, 460},
        fx: 0,
        fy: 0,
        interpolation: Evision.Constant.cv_INTER_LINEAR_EXACT()
      )

    gray = Evision.cvtColor(img, Evision.Constant.cv_COLOR_BGR2GRAY())
    gray = Evision.equalizeHist(gray)

    faces =
      Evision.CascadeClassifier.detectMultiScale(cascade, gray,
        scaleFactor: 1.1,
        minNeighbors: 3,
        flags: 0,
        minSize: {30, 30}
      )

    IO.inspect(faces)

    if Enum.count(faces) > 0 do
      faces_tensor =
        Nx.reshape(
          Nx.tensor(List.flatten(Enum.map(faces, &Tuple.to_list/1)), type: :u8),
          {:auto, 4}
        )

      shapes = Evision.Face.Facemark.fit(model, img, faces_tensor)
      shapes = Enum.map(shapes, &Nx.squeeze(Evision.Mat.to_nx(&1, Nx.BinaryBackend)))
      IO.inspect(shapes)

      img_faces =
        for face <- faces, reduce: img do
          acc ->
            Evision.rectangle(acc, face, {255, 0, 0})
        end

      img_faces =
        for face_shape <- shapes, reduce: img_faces do
          acc ->
            {num_points, 2} = face_shape.shape

            for point_index <- 0..(num_points - 1), reduce: acc do
              acc_inner ->
                Evision.circle(
                  acc_inner,
                  List.to_tuple(Nx.to_flat_list(Nx.as_type(face_shape[point_index], :u8))),
                  3,
                  {255, 255, 255},
                  thickness: Evision.Constant.cv_FILLED()
                )
            end
        end

      save_png(img_faces, "priv/faces/face.png")

      bin = File.read!("priv/faces/face.png")

      hash =
        :sha256
        |> :crypto.hash(bin)
        |> Base.encode16()
        |> String.downcase()

      %{
        dimensions: {elem(img.shape, 1), elem(img.shape, 0)},
        faces: faces,
        path: "/faces/face.png",
        hash: hash
      }
    else
      %{
        dimensions: {elem(img.shape, 1), elem(img.shape, 0)},
        faces: [],
        path: nil,
        hash: nil
      }
    end
  end
end

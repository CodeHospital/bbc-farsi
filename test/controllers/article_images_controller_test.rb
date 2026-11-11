require "test_helper"

class ArticleImagesControllerTest < ActionDispatch::IntegrationTest
  setup { @article = create_article(attrs: { url: "https://bbc.co.uk/news/image-proxy-1" }) }

  test "serves the article's stored image from our own host" do
    @article.update_columns(image_url: "https://ichef.bbci.co.uk/news/1.jpg")
    Resolv.stub(:getaddresses, [ "151.101.0.81" ]) do
      stub_request(:get, "https://ichef.bbci.co.uk/news/1.jpg")
        .to_return(status: 200, body: "JPEGBYTES", headers: { "Content-Type" => "image/jpeg" })

      get article_image_path(@article)
    end

    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_equal "JPEGBYTES", response.body
  end

  test "404 when the article has no image" do
    get article_image_path(@article)
    assert_response :not_found
  end

  test "refuses an image host that resolves to an internal address" do
    @article.update_columns(image_url: "http://internal.example/secret.jpg")
    Resolv.stub(:getaddresses, [ "10.0.0.5" ]) { get article_image_path(@article) }
    assert_response :not_found
  end

  test "refuses a non-image response" do
    @article.update_columns(image_url: "https://ichef.bbci.co.uk/news/page")
    Resolv.stub(:getaddresses, [ "151.101.0.81" ]) do
      stub_request(:get, "https://ichef.bbci.co.uk/news/page")
        .to_return(status: 200, body: "<html>", headers: { "Content-Type" => "text/html" })
      get article_image_path(@article)
    end
    assert_response :bad_gateway
  end
end

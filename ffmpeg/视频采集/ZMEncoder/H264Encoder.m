//
//  H264Encoder.m
//  视频采集
//
//  Created by  luzhaoyang on 17/8/6.
//  Copyright © 2017年 Kingstong. All rights reserved.
//

#import "H264Encoder.h"
#import "avformat.h"  //  build Setting 里面设置Header Search Path
#import "avcodec.h"


@interface H264Encoder()
{
    AVFormatContext *pFormatCtx;
    AVFrame *pFrame;
    AVStream *pStream;
    uint8_t *buffer;
    AVCodecContext *pCodeCtx;
    AVPacket packet;
    
    int frameIndex;
}

@end

@implementation H264Encoder

# pragma - mark 准备编码工作
- (void)prepareEncodeWithWidth:(int)width height: (int)height;
{
    frameIndex = 0;
    
    // 1.注册所有的储存格式和编码格式
    av_register_all(); // bitcode 设置为No 添加依赖库libz 和 libbz 和 libiocn
    
    // 2.创建AVFormatContext
    // 2.1创建AVFomateContext
    pFormatCtx = avformat_alloc_context();
    
    // 2.2创建出一个输出流
    NSString *filePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true) firstObject] stringByAppendingPathComponent:@"abc.h264"];
    AVOutputFormat *pOutputFmt = av_guess_format(NULL, [filePath UTF8String], NULL);
    pFormatCtx ->oformat = pOutputFmt;
    
    // 2.3打开输出流
    if (avio_open(&pFormatCtx->pb, [filePath UTF8String], AVIO_FLAG_READ_WRITE) < 0){
        NSLog(@"打开文件失败");
        return;
    };
    
    // 3.创建AVStream
    // 3.1创建一个流
    pStream = avformat_new_stream(pFormatCtx, 0);
    
    if (pStream == NULL) {
        NSLog(@"创建pStream失败");
        return;
    }
    
    // 3.3 创建time_base(用于计算pts/dts) num:分子  den:分母
    pStream->time_base.num = 1;
    pStream->time_base.den = 90000; // 采样率
    
    // 4.获取AVCodecContext : 包含了编码所有的额参数
    // 4.1从AVStream中取出AVCodecContext
    pCodeCtx = pStream->codec;
    
    // 4.2设置编码的数据是音频还是视频
    pCodeCtx->codec_type = AVMEDIA_TYPE_VIDEO;
    
    // 4.3设置编码标准
    pCodeCtx->codec_id = AV_CODEC_ID_H264;
    
    // 4.4设置图片的格式
    pCodeCtx->pix_fmt = AV_PIX_FMT_YUV420P;
    
    // 4.5设置宽度和高度
    pCodeCtx->width = width;
    pCodeCtx->height = height;
    
    // 4.6最大B帧的个数
    pCodeCtx->max_b_frames = 3;
    
    // 4.7设置一个帧率
    pCodeCtx->time_base.num = 1;
    pCodeCtx->time_base.den = 24;
    
    // 4.8设置GUP的大小
    pCodeCtx->gop_size = 30;
    
    // 4.9设置bit率
    pCodeCtx->bit_rate = 1500000;
    
    // 4.10设置最大和最小的音频质量
    pCodeCtx->qmin = 10;
    pCodeCtx->qmax = 51;
    
    // 5.查找AVCodec
    // 5.1查找编码器
    AVCodec *pCodec = avcodec_find_encoder(pCodeCtx->codec_id);
    
    // 5.2判断是佛为NULL
    if (pCodec == NULL) {
        NSLog(@"查找编码器失败");
        return;
    }
    
    // 5.3打开编码器
    // 如果是H264的编码的标准
    AVDictionary *options = NULL;
    // 设置视屏的编码和视屏质量的负载平衡
    av_dict_set(&options, "preset", "slow", 0);
    av_dict_set(&options, "tune", "zerolatency", 0);
    if (avcodec_open2(pCodeCtx, pCodec, &options) < 0){
        NSLog(@"打开编码器失败");
        return;
    };
    
    // 6.创建AVframe --> AVPacket
    pFrame = av_frame_alloc();
    avpicture_fill((AVPicture *)pFrame, buffer, AV_PIX_FMT_YUV420P, width, height);
}

# pragma - mark 开示编码
- (void)encodeFrame:(CMSampleBufferRef)sampleBuffer
{
    
   // 0.设置pts -> presentation time stamp  编码时间
   // dts -> Decoder time stamp 解码时间
    
   // 1.CMSampleBufferRef获取CVPixeBufferRef
    CVPixelBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
   // 2.锁定内存地址CVPixeBufferRef
    if (CVPixelBufferLockBaseAddress(imageBuffer, 0) == 0) {
        
        // 3.从CVPixeBufferRef中获取YUV的数据
        // NV12和NV21属于YUV格式,是一种two-plane模式,既Y和UV分为两个plane, 但是UV(CbCr)为交错储存,而不是分为三个plane
        
        // YUV420
        // 4:4:4  YUV444
        // 4:2:2  YUV422
        // 4:1:1  YUV420 最后一个通道没有东西 最后一个通道放到了第二个通道  YYYYYYYY UVUV  :two plane
        
        // 3.1获取Y分量的地址
        UInt8 *bufferPtr = (UInt8 *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
        
        // 3.2获取UV分量的地址
        UInt8 *bufferPtr1 = (UInt8 *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1);
        
        // 3.3根据像素获取图片真实的宽度和高度
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        
        // 获取Y分量的长度
        size_t yBPR = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
        size_t uvBPR = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1);
        
        // Y: width * height
        // U: width * height / 4
        // V: width * height / 4
        
        UInt8 *yuv420_data = (UInt8 *)malloc(width * height * 3/2);
        
        // 3.4将NV12数据转化成YUV420数据
        // Ios默认采集的NV12数据 --> YUV420P
        UInt8 *pU = yuv420_data + width * height;
        UInt8 *pV = pU + width * height / 4;
        for (int i = 0; i < height; i++) {
            memcpy(yuv420_data + i * width, bufferPtr + i * yBPR, width);
        }
        
        for (int j = 0; j < height/2; j++)
        {
            for (int i = 0; i < width/2; i++) {
                *(pU++) = bufferPtr1[i<<1];
                *(pV++) = bufferPtr1[(i<<1) + 1];
            }
            bufferPtr1 += uvBPR;
        }
        
        // 4.设置AVFrame的属性
        // 4.1设置YUV数据到AVframe
        pFrame->data[0] = yuv420_data;
        pFrame->data[1] = yuv420_data + width * height;
        pFrame->data[2] = yuv420_data + width * height * 5/4;
//        frameIndex ++;
//        pFrame->pts = frameIndex;
        
        // 4.2设置宽度和高度
        pFrame->width = (int)width;
        pFrame->height = (int)height;
        
        // 4.3设置格式
        pFrame->format = AV_PIX_FMT_YUV420P;
        
        // 5.开始进行编码操作
        int got_picture = 0;
        
        if (avcodec_encode_video2(pCodeCtx, &packet, pFrame, &got_picture) < 0){
            NSLog(@"编码失败");
            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
            return;
        };
        
        // 6.将AVPacket写入文件
        if (got_picture) {
            
            // 6.1设置AVPacket的stream_index
            packet.stream_index = pStream->index;
            
            // 6.2将pachket写入文件
            av_write_frame(pFormatCtx, &packet);
            
            // 6.3释放资源
//            av_free_packet(&packet);
        }
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    }
}

- (void)endEnocde
{
    // 1.将AVFormatcontent中没有写入的文件全部写入
    av_write_trailer(pFormatCtx);
    
    // 2.释放资源
    avio_close(pFormatCtx->pb);
    avcodec_close(pCodeCtx);
    free(pFrame);
    free(pFormatCtx);
}

@end
